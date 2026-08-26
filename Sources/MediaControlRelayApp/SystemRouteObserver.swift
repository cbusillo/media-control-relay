import AppKit
import ColorSync
import CoreAudio
import CoreGraphics
import MediaControlCore

@MainActor
protocol RouteObserving: AnyObject {
    var onSnapshot: ((RouteSnapshot) -> Void)? { get set }
    var onStateChange: ((RouteObservationState) -> Void)? { get set }
    var onSleep: (() -> Void)? { get set }
    var onWake: (() -> Void)? { get set }

    var state: RouteObservationState { get }

    func start()
    func stop()
}

@MainActor
final class InactiveRouteObserver: RouteObserving {
    var onSnapshot: ((RouteSnapshot) -> Void)?
    var onStateChange: ((RouteObservationState) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    let state: RouteObservationState = .stopped

    func start() {}

    func stop() {}
}

@MainActor
final class SystemRouteObserver: RouteObserving {
    var onSnapshot: ((RouteSnapshot) -> Void)?
    var onStateChange: ((RouteObservationState) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private var lifecycle = RouteObservationLifecycle()
    private var coalescer = RouteObservationCoalescer()
    private var displayNotificationToken: NSObjectProtocol?
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var audioPropertyListener: AudioObjectPropertyListenerBlock?
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingFlushTask: Task<Void, Never>?
    private let workspaceNotificationCenter: NotificationCenter

    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var state: RouteObservationState {
        lifecycle.state
    }

    init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func start() {
        guard lifecycle.start() == .registerRouteObserversAndPublishFreshSnapshot else {
            return
        }
        onStateChange?(lifecycle.state)
        registerWorkspaceObservers()
        registerRouteObservers()
        resetAndPublishFreshSnapshot()
    }

    func stop() {
        guard lifecycle.stop() == .unregisterRouteObservers else {
            return
        }
        onStateChange?(lifecycle.state)
        unregisterRouteObservers()
        unregisterWorkspaceObservers()
        resetPendingObservation()
    }

    private func sleep() {
        guard lifecycle.sleep() == .unregisterRouteObservers else {
            return
        }
        onStateChange?(lifecycle.state)
        unregisterRouteObservers()
        resetPendingObservation()
        onSleep?()
    }

    private func wake() {
        guard lifecycle.wake() == .registerRouteObserversAndPublishFreshSnapshot else {
            return
        }
        onStateChange?(lifecycle.state)
        registerRouteObservers()
        resetAndPublishFreshSnapshot()
        onWake?()
    }

    private func registerRouteObservers() {
        registerDisplayObserver()
        registerAudioObserver()
    }

    private func unregisterRouteObservers() {
        if let displayNotificationToken {
            NotificationCenter.default.removeObserver(displayNotificationToken)
            self.displayNotificationToken = nil
        }

        if let audioPropertyListener {
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputAddress,
                DispatchQueue.main,
                audioPropertyListener
            )
            if status == noErr {
                self.audioPropertyListener = nil
            }
        }
    }

    private func unregisterWorkspaceObservers() {
        for token in workspaceNotificationTokens {
            workspaceNotificationCenter.removeObserver(token)
        }
        workspaceNotificationTokens.removeAll()
    }

    private func resetAndPublishFreshSnapshot() {
        resetPendingObservation()
        publishFreshSnapshot()
    }

    private func resetPendingObservation() {
        cancelRefreshTasks()
        coalescer.reset()
    }

    private func registerDisplayObserver() {
        guard displayNotificationToken == nil else {
            return
        }
        displayNotificationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }
    }

    private func registerWorkspaceObservers() {
        guard workspaceNotificationTokens.isEmpty else {
            return
        }
        let center = workspaceNotificationCenter
        workspaceNotificationTokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleep()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.wake()
                }
            },
        ]
    }

    private func registerAudioObserver() {
        guard audioPropertyListener == nil else {
            return
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main,
            listener
        )
        if status == noErr {
            audioPropertyListener = listener
        }
    }

    private func scheduleRefresh() {
        guard lifecycle.state == .observing, pendingRefreshTask == nil else {
            return
        }
        pendingRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            pendingRefreshTask = nil
            refreshSnapshot()
        }
    }

    private func refreshSnapshot() {
        guard lifecycle.state == .observing else {
            return
        }
        let event = coalescer.receive(
            currentSnapshot(),
            at: ProcessInfo.processInfo.systemUptime
        )
        handle(event)
    }

    private func publishFreshSnapshot() {
        let event = coalescer.receive(
            currentSnapshot(),
            at: ProcessInfo.processInfo.systemUptime
        )
        handle(event)
    }

    private func handle(_ event: RouteObservationCoalescerEvent) {
        switch event {
        case .ignored:
            return
        case let .publish(snapshot):
            onSnapshot?(snapshot)
        case let .scheduled(deadline):
            scheduleFlush(at: deadline)
        }
    }

    private func scheduleFlush(at deadline: TimeInterval) {
        pendingFlushTask?.cancel()
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        pendingFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            pendingFlushTask = nil
            handle(coalescer.flush(at: ProcessInfo.processInfo.systemUptime))
        }
    }

    private func cancelRefreshTasks() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
    }

    private func currentSnapshot() -> RouteSnapshot {
        RouteSnapshotNormalizer.normalize(
            audioOutput: currentAudioOutput(),
            displays: currentDisplays()
        )
    }

    private func currentAudioOutput() -> AudioOutputObservation? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }
        return AudioOutputObservation(
            name: stringProperty(
                deviceID: deviceID,
                selector: kAudioObjectPropertyName
            ),
            stableIdentifier: stringProperty(
                deviceID: deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ),
            transportKind: transportKind(
                rawValue: uint32Property(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyTransportType
                )
            )
        )
    }

    private func currentDisplays() -> [DisplayObservation] {
        NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            guard CGDisplayIsActive(displayID) != 0 else {
                return nil
            }
            return DisplayObservation(
                name: screen.localizedName,
                stableIdentifier: displayUUID(for: displayID)
            )
        }
    }

    private func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    private func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private func uint32Property(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func transportKind(rawValue: UInt32?) -> AudioTransportKind {
        guard let rawValue else {
            return .unknown
        }
        switch rawValue {
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeBluetooth:
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI:
            return .display
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        default:
            return .unknown
        }
    }
}
