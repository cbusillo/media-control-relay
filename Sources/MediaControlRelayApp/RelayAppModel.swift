import AppKit
import CoreGraphics
import MediaControlCore
import Observation

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
    var activationMatches = false
    var commandsRecorded = 0
    var commandsSuppressed = 0
    var targetConfiguration: RelayConfiguration?

    let productStatus: LocalizedStringResource = "Preview build"

    private let volumeKeyMonitor = EventTapVolumeKeyMonitor()
    private let volumeKeyGestureMonitor: VolumeKeyGestureMonitor
    private let routeObserver: any RouteObserving
    private let configurationStore: RelayConfigurationStore
    private let coordinator: RelayCoordinator
    private var volumeKeyTask: Task<Void, Never>?
    private var volumeActionTask: Task<Void, Never>?
    private let inputMonitoringRequestedKey = "inputMonitoringAccessRequested"
    private var requestedInputMonitoringThisLaunch = false

    init(
        routeObserver: any RouteObserving = SystemRouteObserver(),
        configurationStore: RelayConfigurationStore = RelayConfigurationStore()
    ) {
        let gestureMonitor = VolumeKeyGestureMonitor()
        self.volumeKeyGestureMonitor = gestureMonitor
        self.routeObserver = routeObserver
        self.configurationStore = configurationStore
        self.coordinator = RelayCoordinator(
            configuration: configurationStore.load(),
            cancelHeldGesture: {
                gestureMonitor.cancel()
            }
        )
        targetConfiguration = coordinator.configuration
        relayState = coordinator.relayState

        let events = volumeKeyMonitor.events
        volumeKeyTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else {
                    return
                }
                self.record(event)
            }
        }

        let actions = volumeKeyGestureMonitor.actions
        volumeActionTask = Task { @MainActor [weak self] in
            for await action in actions {
                guard !Task.isCancelled, let self else {
                    return
                }
                self.record(action)
            }
        }
        routeObserver.onSnapshot = { [weak self] snapshot in
            guard let self else {
                return
            }
            routeSnapshot = snapshot
            apply(.routeSnapshot(snapshot))
        }
        routeObserver.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            routeObservationState = state
            apply(.routeObservationState(state))
        }
        routeObserver.onSleep = { [weak self] in
            self?.volumeKeyGestureMonitor.cancel()
        }
        routeObserver.start()
        refreshInputMonitoring()
        apply(.transportReachability(.reachable))
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

    var statusCopy: RelayStatusCopy {
        RelayStatusCopyCatalog.copy(
            for: relayState,
            targetKind: targetConfiguration?.target.kind
        )
    }

    var configuredDeviceName: String {
        targetConfiguration?.target.name ?? "No preview target selected"
    }

    var selectedPreviewRouteDescription: String {
        guard let configuration = targetConfiguration else {
            return "No preview route selected"
        }
        let displayRequirement = configuration.activationRule.requiresDisplay
            ? "display required"
            : "audio-only matching"
        return "Audio: \(configuration.activationRule.audioOutputMatch) (\(displayRequirement))"
    }

    var canCreatePreviewTarget: Bool {
        RelayConfigurationFactory.preview(for: routeSnapshot) != nil
    }

    var previewTargetExplanation: LocalizedStringResource {
        "The preview target is an in-process recording sink. It does not connect to or control a TV or other media device, and it does not intercept or suppress normal Mac volume handling."
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
            "setup_complete": targetConfiguration == nil ? "no" : "yes",
            "target_kind": targetConfiguration?.target.kind.rawValue ?? "unconfigured",
            "activation": targetConfiguration == nil
                ? "unconfigured"
                : activationMatches ? "match" : "no-match",
            "commands_recorded": commandsRecorded.formatted(),
            "actions_not_recorded": commandsSuppressed.formatted(),
            "volume_actions_emitted": observedVolumeActionCount.formatted(),
            "volume_events_observed": observedVolumeKeyEventCount.formatted(),
            "target_connection": targetConfiguration == nil
                ? "not-available"
                : "preview-sink",
        ].merging(routeDiagnostics) { current, _ in current }
        let allowedFieldNames: Set<String> = [
            "app_version",
            "relay_state",
            "input_monitoring",
            "macos_version",
            "product_status",
            "setup_complete",
            "target_kind",
            "activation",
            "commands_recorded",
            "actions_not_recorded",
            "volume_actions_emitted",
            "volume_events_observed",
            "target_connection",
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

    func createPreviewTarget() {
        guard let configuration = RelayConfigurationFactory.preview(for: routeSnapshot) else {
            return
        }
        configurationStore.save(configuration)
        apply(.configuration(configuration))
        apply(.transportReachability(.reachable))
    }

    func removePreviewTarget() {
        configurationStore.remove()
        apply(.configuration(nil))
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
        apply(.inputMonitoringAuthorization(inputMonitoringAuthorization))

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
            apply(.inputMonitoringAuthorization(.denied))
        }
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
            return "Let Media Control Relay detect Volume Up, Volume Down, and Mute."
        case .requested:
            return "Quit and reopen Media Control Relay to apply your choice."
        case .denied:
            return "Turn on access in Privacy & Security, then reopen the app."
        case .granted:
            return "Volume key access is ready on this Mac."
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

    private func apply(_ event: RelayRoutingEvent) {
        coordinator.apply(event)
        relayState = coordinator.relayState
        activationMatches = coordinator.activationMatches
        commandsRecorded = coordinator.recordedCommandCount
        commandsSuppressed = coordinator.suppressedCommandCount
        targetConfiguration = coordinator.configuration
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
        apply(.volumeAction(action))
    }
}

extension RelayState {
    var diagnosticName: String {
        switch self {
        case .unconfigured: "unconfigured"
        case .unsupported: "unsupported"
        case .needsPermission: "needs-permission"
        case .needsLocalNetworkPermission: "needs-local-network-permission"
        case .dormant: "dormant"
        case .checkingTarget: "checking-target"
        case .offline: "offline"
        case .active: "active"
        }
    }
}
