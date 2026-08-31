import AppKit
import CoreGraphics
import MediaControlCore

private let systemDefinedEventTypeRawValue: UInt32 = 14

enum VolumeKeyMonitorError: Error {
    case eventTapUnavailable
    case runLoopSourceUnavailable
}

@MainActor
protocol VolumeKeyMonitoring: AnyObject {
    var events: AsyncStream<VolumeKeyEvent> { get }
    var suppressionMode: VolumeKeySuppressionMode { get }

    func setSuppressionMode(_ mode: VolumeKeySuppressionMode)
    func setSuppressionTiming(_ timing: VolumeKeySuppressionTiming)
    func updateSuppressionAuthority(_ authority: VolumeKeySuppressionAuthority?)
    func revokeSuppressionAuthority()
    func start() throws
    func stop()
}

extension VolumeKeyMonitoring {
    var suppressionMode: VolumeKeySuppressionMode { .listenOnly }

    func setSuppressionMode(_: VolumeKeySuppressionMode) {}

    func setSuppressionTiming(_: VolumeKeySuppressionTiming) {}

    func updateSuppressionAuthority(_: VolumeKeySuppressionAuthority?) {}

    func revokeSuppressionAuthority() {}
}

private final class VolumeKeyEventTapContext {
    let continuation: AsyncStream<VolumeKeyEvent>.Continuation
    var eventTap: CFMachPort?
    var suppressionMode: VolumeKeySuppressionMode = .listenOnly
    var suppressionAuthority: VolumeKeySuppressionAuthority?
    var suppressionState = VolumeKeySuppressionState()
    var maximumLatchIdle: TimeInterval

    init(
        continuation: AsyncStream<VolumeKeyEvent>.Continuation,
        maximumLatchIdle: TimeInterval
    ) {
        self.continuation = continuation
        self.maximumLatchIdle = maximumLatchIdle
    }
}

@MainActor
final class EventTapVolumeKeyMonitor: VolumeKeyMonitoring {
    let events: AsyncStream<VolumeKeyEvent>

    private let context: VolumeKeyEventTapContext
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedContext: UnsafeMutableRawPointer?
    private var requestedSuppressionMode: VolumeKeySuppressionMode = .listenOnly

    private(set) var suppressionMode: VolumeKeySuppressionMode = .listenOnly

    var isRunning: Bool {
        eventTap != nil
    }

    init(timing: VolumeKeySuppressionTiming = .default) {
        let stream = AsyncStream<VolumeKeyEvent>.makeStream()
        events = stream.stream
        context = VolumeKeyEventTapContext(
            continuation: stream.continuation,
            maximumLatchIdle: timing.maximumLatchIdle
        )
    }

    func setSuppressionMode(_ mode: VolumeKeySuppressionMode) {
        let shouldRestart = eventTap != nil && requestedSuppressionMode != mode
        requestedSuppressionMode = mode
        if shouldRestart {
            stopEventTap()
        }
    }

    func setSuppressionTiming(_ timing: VolumeKeySuppressionTiming) {
        context.maximumLatchIdle = timing.maximumLatchIdle
    }

    func updateSuppressionAuthority(_ authority: VolumeKeySuppressionAuthority?) {
        context.suppressionAuthority = authority
    }

    func revokeSuppressionAuthority() {
        context.suppressionAuthority = nil
    }

    func start() throws {
        guard eventTap == nil else {
            return
        }

        let systemDefinedEventType = CGEventType(
            rawValue: systemDefinedEventTypeRawValue
        )!
        let eventMask = CGEventMask(1) << systemDefinedEventType.rawValue
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        let preferredOptions: CGEventTapOptions = requestedSuppressionMode == .conditional
            ? .defaultTap
            : .listenOnly
        let preferredTap = makeEventTap(
            options: preferredOptions,
            eventMask: eventMask,
            contextPointer: contextPointer
        )
        let eventTap = preferredTap ?? (
            requestedSuppressionMode == .conditional
                ? makeEventTap(
                    options: .listenOnly,
                    eventMask: eventMask,
                    contextPointer: contextPointer
                )
                : nil
        )
        guard let eventTap else {
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw VolumeKeyMonitorError.eventTapUnavailable
        }
        suppressionMode = preferredTap == nil ? .listenOnly : requestedSuppressionMode
        context.suppressionMode = suppressionMode
        if suppressionMode == .listenOnly {
            context.suppressionAuthority = nil
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw VolumeKeyMonitorError.runLoopSourceUnavailable
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        retainedContext = contextPointer
        context.eventTap = eventTap
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        stopEventTap()
        context.suppressionState = VolumeKeySuppressionState()
    }

    private func makeEventTap(
        options: CGEventTapOptions,
        eventMask: CGEventMask,
        contextPointer: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: eventMask,
            callback: volumeKeyEventTapCallback,
            userInfo: contextPointer
        )
    }

    private func stopEventTap() {
        context.suppressionAuthority = nil
        context.suppressionState = VolumeKeySuppressionState()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        context.eventTap = nil
        context.suppressionMode = .listenOnly
        suppressionMode = .listenOnly
        runLoopSource = nil
        eventTap = nil
        if let retainedContext {
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(retainedContext)
                .release()
        }
        retainedContext = nil
    }
}

@MainActor
final class InactiveVolumeKeyMonitor: VolumeKeyMonitoring {
    let events = AsyncStream<VolumeKeyEvent> { continuation in
        continuation.finish()
    }

    func start() throws {}

    func stop() {}
}

private func volumeKeyEventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard Thread.isMainThread else {
        return Unmanaged.passUnretained(event)
    }
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<VolumeKeyEventTapContext>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.suppressionAuthority = nil
        context.suppressionState = VolumeKeySuppressionState()
        if let eventTap = context.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == systemDefinedEventTypeRawValue,
          let appKitEvent = NSEvent(cgEvent: event),
          let decoded = SystemDefinedKeyDecoder.decode(
              subtype: Int(appKitEvent.subtype.rawValue),
              data1: appKitEvent.data1,
              timestamp: appKitEvent.timestamp
          ) else {
        return Unmanaged.passUnretained(event)
    }

    let passthroughModifiers: NSEvent.ModifierFlags = [
        .shift,
        .option,
        .command,
        .control,
    ]
    if !appKitEvent.modifierFlags.intersection(passthroughModifiers).isEmpty,
       context.suppressionState.latchedActions[decoded.action] == nil {
        return Unmanaged.passUnretained(event)
    }

    context.continuation.yield(decoded)
    let evaluation = VolumeKeySuppressionPolicy.evaluate(
        event: decoded,
        mode: context.suppressionMode,
        authority: context.suppressionAuthority,
        state: context.suppressionState,
        uptime: ProcessInfo.processInfo.systemUptime,
        maximumLatchIdle: context.maximumLatchIdle
    )
    context.suppressionState = evaluation.state
    return evaluation.decision == .consume
        ? nil
        : Unmanaged.passUnretained(event)
}
