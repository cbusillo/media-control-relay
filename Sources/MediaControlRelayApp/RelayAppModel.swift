import AppKit
import CoreGraphics
import Observation
import MediaControlCore

@MainActor
@Observable
final class RelayAppModel {
    var relayState: RelayState = .unconfigured
    var launchAtLogin = false
    var inputMonitoringAuthorization: InputMonitoringAuthorization = .notDetermined
    var inputMonitoringUnavailable = false
    var observedVolumeKeyEventCount = 0
    var observedVolumeKeyPressCount = 0
    var observedVolumeActionCount = 0
    var lastObservedVolumeAction: VolumeAction?
    var routeSnapshot = RouteSnapshot(audioOutput: nil, displays: [])
    var routeObservationState: RouteObservationState = .stopped

    let productStatus: LocalizedStringResource = "Preview build"
    let configuredDeviceName: LocalizedStringResource = "No media target selected"

    private let volumeKeyMonitor = EventTapVolumeKeyMonitor()
    private let volumeKeyGestureMonitor = VolumeKeyGestureMonitor()
    private let routeObserver: any RouteObserving
    private var volumeKeyTask: Task<Void, Never>?
    private var volumeActionTask: Task<Void, Never>?
    private let inputMonitoringRequestedKey = "inputMonitoringAccessRequested"
    private var requestedInputMonitoringThisLaunch = false

    init(routeObserver: any RouteObserving = SystemRouteObserver()) {
        self.routeObserver = routeObserver

        let events = volumeKeyMonitor.events
        volumeKeyTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                self?.record(event)
            }
        }

        let actions = volumeKeyGestureMonitor.actions
        volumeActionTask = Task { @MainActor [weak self] in
            for await action in actions {
                guard !Task.isCancelled else {
                    return
                }
                self?.record(action)
            }
        }
        routeObserver.onSnapshot = { [weak self] snapshot in
            self?.routeSnapshot = snapshot
        }
        routeObserver.onStateChange = { [weak self] state in
            self?.routeObservationState = state
        }
        routeObserver.onSleep = { [weak self] in
            self?.volumeKeyGestureMonitor.cancel()
        }
        routeObserver.start()
        refreshInputMonitoring()
    }

    var buildDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var diagnosticsSummary: String {
        let routeDiagnostics = RouteObservationDiagnostics(
            state: routeObservationState,
            snapshot: routeSnapshot
        ).fields
        let fields = [
            "app_version": buildDescription,
            "relay_state": relayState.diagnosticName,
            "input_monitoring": inputMonitoringDiagnosticName,
            "macos_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "product_status": "preview",
            "setup_complete": "no",
            "target_connection": "not-available",
            "volume_actions_emitted": observedVolumeActionCount.formatted(),
            "volume_events_observed": observedVolumeKeyEventCount.formatted(),
        ].merging(routeDiagnostics) { current, _ in current }
        let allowedFieldNames: Set<String> = [
            "app_version",
            "relay_state",
            "input_monitoring",
            "macos_version",
            "product_status",
            "setup_complete",
            "target_connection",
            "volume_actions_emitted",
            "volume_events_observed",
            "route_observation",
            "audio_transport",
            "active_displays",
        ]
        return DiagnosticsRedaction.redact(
            fields: DiagnosticsRedaction.allowlisted(
                fields: fields,
                allowedFieldNames: allowedFieldNames
            )
        )
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsSummary, forType: .string)
    }

    func requestInputMonitoring() {
        UserDefaults.standard.set(true, forKey: inputMonitoringRequestedKey)
        requestedInputMonitoringThisLaunch = true
        _ = CGRequestListenEventAccess()
        refreshInputMonitoring()
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshInputMonitoring() {
        inputMonitoringAuthorization = InputMonitoringDecision.resolve(
            preflightGranted: CGPreflightListenEventAccess(),
            hasRequestedAccess: UserDefaults.standard.bool(
                forKey: inputMonitoringRequestedKey
            ),
            requestedThisLaunch: requestedInputMonitoringThisLaunch
        )

        guard inputMonitoringAuthorization == .granted else {
            volumeKeyMonitor.stop()
            volumeKeyGestureMonitor.cancel()
            inputMonitoringUnavailable = false
            return
        }

        do {
            try volumeKeyMonitor.start()
            inputMonitoringUnavailable = false
        } catch {
            inputMonitoringUnavailable = true
        }
    }

    var activationSnapshot: ActivationSnapshot {
        routeSnapshot.activationSnapshot
    }

    var inputMonitoringTitle: LocalizedStringResource {
        if inputMonitoringUnavailable {
            return "Volume key listening is unavailable"
        }
        switch inputMonitoringAuthorization {
        case .notDetermined: return "Volume key access is not set up"
        case .requested: return "Volume key access needs a restart"
        case .denied: return "Volume key access needs attention"
        case .granted: return "Volume key access is ready"
        }
    }

    var inputMonitoringDetail: LocalizedStringResource {
        if inputMonitoringUnavailable {
            return "Quit and reopen Media Control Relay, then check access again."
        }
        switch inputMonitoringAuthorization {
        case .notDetermined:
            return "Allow access so Media Control Relay can detect Volume Up, Volume Down, and Mute. Typed keys are never delivered to the app."
        case .requested:
            return "Complete the macOS prompt, then quit and reopen Media Control Relay to apply your choice."
        case .denied:
            return "Turn on Media Control Relay in Privacy & Security > Input Monitoring, then quit and reopen the app."
        case .granted:
            return "Press Volume Up, Volume Down, or Mute to confirm that this Mac can detect the controls."
        }
    }

    var inputMonitoringSetupDetail: LocalizedStringResource {
        if inputMonitoringUnavailable {
            return "Quit and reopen Media Control Relay, then check access in Settings."
        }
        switch inputMonitoringAuthorization {
        case .notDetermined:
            return "Let Media Control Relay detect Volume Up, Volume Down, and Mute."
        case .requested:
            return "Quit and reopen Media Control Relay to apply your choice."
        case .denied:
            return "Turn on access in Privacy & Security, then reopen the app."
        case .granted:
            return "Volume key access is ready on this Mac."
        }
    }

    var inputMonitoringSystemImage: String {
        if inputMonitoringUnavailable {
            return "exclamationmark.triangle"
        }
        switch inputMonitoringAuthorization {
        case .notDetermined: return "hand.raised"
        case .requested: return "arrow.clockwise.circle"
        case .denied: return "hand.raised.slash"
        case .granted: return "checkmark.circle.fill"
        }
    }

    var lastObservedVolumeActionTitle: LocalizedStringResource? {
        switch lastObservedVolumeAction {
        case .up: return "Volume Up"
        case .down: return "Volume Down"
        case .mute: return "Mute"
        case nil: return nil
        }
    }

    private var inputMonitoringDiagnosticName: String {
        if inputMonitoringUnavailable {
            return "unavailable"
        }
        switch inputMonitoringAuthorization {
        case .notDetermined: return "not-determined"
        case .requested: return "requested"
        case .denied: return "denied"
        case .granted: return "granted"
        }
    }

    private func record(_ event: VolumeKeyEvent) {
        observedVolumeKeyEventCount += 1
        if event.phase == .pressed, !event.isRepeat {
            observedVolumeKeyPressCount += 1
        }
        volumeKeyGestureMonitor.ingest(event)
    }

    private func record(_ action: VolumeAction) {
        observedVolumeActionCount += 1
        lastObservedVolumeAction = action
    }
}

extension RelayState {
    var title: LocalizedStringResource {
        switch self {
        case .unconfigured: "Media target setup is coming soon"
        case .unsupported: "This media target isn’t supported"
        case .needsPermission: "Allow volume key access"
        case .dormant: "Using Mac volume"
        case .offline: "Can’t reach your media target"
        case .active: "Controlling media volume"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .unconfigured:
            "This preview shows the setup flow but can’t connect to a media target yet."
        case .unsupported:
            "Choose another media target or check the compatibility list."
        case .needsPermission:
            "Allow Media Control Relay to detect your Mac’s volume and mute keys."
        case .dormant:
            "Your selected media target isn’t the current audio and display route, so your Mac handles the volume keys."
        case .offline:
            "Make sure the media target is on and connected to the same network as your Mac."
        case .active:
            "Your Mac’s volume and mute keys are controlling the selected media device."
        }
    }

    var localizedTitle: String {
        String(localized: title)
    }

    var systemImage: String {
        switch self {
        case .active: "speaker.wave.2.fill"
        case .dormant: "speaker.wave.2"
        case .offline: "wifi.exclamationmark"
        case .needsPermission: "hand.raised.fill"
        case .unsupported: "tv.badge.xmark"
        case .unconfigured: "tv.badge.wifi"
        }
    }

    var diagnosticName: String {
        switch self {
        case .unconfigured: "unconfigured"
        case .unsupported: "unsupported"
        case .needsPermission: "needs-permission"
        case .dormant: "dormant"
        case .offline: "offline"
        case .active: "active"
        }
    }
}
