import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import MediaControlCore
import Observation

struct InputMonitoringAccessClient: Sendable {
    let preflight: @Sendable () -> Bool
    let request: @Sendable () -> Void

    static let live = InputMonitoringAccessClient(
        preflight: CGPreflightListenEventAccess,
        request: {
            _ = CGRequestListenEventAccess()
        }
    )

    static let denied = InputMonitoringAccessClient(
        preflight: { false },
        request: {}
    )
}

struct AccessibilityAccessClient: Sendable {
    let preflight: @Sendable () -> Bool
    let request: @Sendable () -> Void

    static let live = AccessibilityAccessClient(
        preflight: AXIsProcessTrusted,
        request: {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    )

    static let denied = AccessibilityAccessClient(
        preflight: { false },
        request: {}
    )
}

@MainActor
@Observable
final class RelayAppModel {
    var relayState: RelayState = .unconfigured
    private(set) var launchAtLoginState: LaunchAtLoginState = .notRegistered
    private(set) var launchAtLoginOperationFailure: LaunchAtLoginOperation?
    var inputMonitoringAuthorization: InputMonitoringAuthorization = .notDetermined
    var inputMonitoringUnavailable = false
    var accessibilityAuthorization: AccessibilityAuthorization = .notDetermined
    private(set) var volumeKeySuppressionMode: VolumeKeySuppressionMode = .listenOnly
    var observedVolumeKeyEventCount = 0
    var observedVolumeKeyPressCount = 0
    var observedVolumeActionCount = 0
    var lastObservedVolumeAction: VolumeAction?
    private(set) var externalVolumeActionsAccepted = 0
    private(set) var externalVolumeActionsRejected = 0
    private(set) var externalVolumeActionsRateLimited = 0
    private(set) var externalRemoteActionsRejected = 0
    private(set) var externalRemoteActionsUnavailable = 0
    var routeSnapshot = RouteSnapshot(audioOutput: nil, displays: [])
    var routeObservationState: RouteObservationState = .stopped
    var activationMatches = false
    var commandsRecorded = 0
    var commandsSuppressed = 0
    var targetCommandsDispatched = 0
    var targetCommandsFailed = 0
    var targetRecoveryAttempts = 0
    var networkTransitionCount = 0
    var networkPathSnapshot = NetworkPathSnapshot.unknown
    var targetConfiguration: RelayConfiguration?
    private(set) var targetPresentationState: MediaTargetPresentationState = .hidden
    private(set) var accessibleTargetStatus: String?
    var presentationInvalidationEpoch: UInt64 { targetPresentation.invalidationEpoch }

    let productStatus: LocalizedStringResource = "Preview build"
    let discovery: MediaTargetDiscoveryModel
    let remoteControl: RemoteControlModel?

    private let volumeKeyMonitor: any VolumeKeyMonitoring
    private let volumeKeyGestureMonitor: VolumeKeyGestureMonitor
    private let routeObserver: any RouteObserving
    private let networkPathObserver: any NetworkPathObserving
    private let configurationStore: RelayConfigurationStore
    private let inputMonitoringAccess: InputMonitoringAccessClient
    private let accessibilityAccess: AccessibilityAccessClient
    private let launchAtLoginClient: LaunchAtLoginClient
    private let volumeKeySuppressionTiming: VolumeKeySuppressionTiming
    private let monotonicTimeProvider: MonotonicTimeProvider
    private let externalVolumeActionDuplicateIntervalNanoseconds: UInt64
    private let targetOverlayPresenter: any TargetOverlayPresenting
    private let mediaTargetSessionFactory: (RelayConfiguration?) -> MediaTargetSession?
    private let coordinator: RelayCoordinator
    private let preferences: UserDefaults
    private var mediaTargetSession: MediaTargetSession?
    private var targetPresentation: MediaTargetPresentationModel
    private var applicationActivationToken: NSObjectProtocol?
    private var applicationTerminationToken: NSObjectProtocol?
    private var volumeKeyTask: Task<Void, Never>?
    private var volumeActionTask: Task<Void, Never>?
    private var targetProbeTask: Task<Void, Never>?
    private var targetProbeGeneration: UInt64 = 0
    private var targetKeepaliveTask: Task<Void, Never>?
    private var targetKeepaliveGeneration: UInt64 = 0
    private var commandContinuation: AsyncStream<TargetCommandRequest>.Continuation?
    private var commandPumpTask: Task<Void, Never>?
    private var commandGeneration: UInt64 = 0
    private var nextPresentationRequestID: UInt64 = 0
    private var repeatedVolumeAction: VolumeAction?
    private var activeHoldGeneration: UInt64 = 0
    private var activePresentationRequest: PendingPresentationRequest?
    private var presentationDismissalTask: Task<Void, Never>?
    private var accessibilityStatusPublicationTask: Task<Void, Never>?
    private var accessibilityStatusPublicationGeneration: UInt64 = 0
    private var awaitingWakeCompletion = false
    private var hasReceivedNetworkPathSnapshot = false
    private let inputMonitoringRequestedKey = "inputMonitoringAccessRequested"
    private var requestedInputMonitoringThisLaunch = false
    private let accessibilityRequestedKey = "accessibilityAccessRequested"
    private var requestedAccessibilityThisLaunch = false
    private var lastExternalVolumeAction: (action: VolumeAction, timestamp: UInt64)?

    private struct TargetCommandRequest: Sendable {
        let command: RelayCommand
        let holdGeneration: UInt64?
    }

    private struct PendingPresentationRequest: Equatable {
        let requestID: UInt64
        let epoch: UInt64
    }

    init(
        routeObserver: any RouteObserving = SystemRouteObserver(),
        networkPathObserver: any NetworkPathObserving = SystemNetworkPathObserver(),
        configurationStore: RelayConfigurationStore = RelayConfigurationStore(),
        volumeKeyMonitor: any VolumeKeyMonitoring = EventTapVolumeKeyMonitor(),
        inputMonitoringAccess: InputMonitoringAccessClient = .live,
        accessibilityAccess: AccessibilityAccessClient = .live,
        launchAtLoginClient: LaunchAtLoginClient = .live,
        applicationNotificationCenter: NotificationCenter = .default,
        discovery: MediaTargetDiscoveryModel = MediaTargetDiscoveryModel(),
        targetPresentationTiming: MediaTargetPresentationTiming = MediaTargetPresentationTiming(),
        volumeKeySuppressionTiming: VolumeKeySuppressionTiming = .default,
        monotonicTimeProvider: MonotonicTimeProvider = .live,
        externalVolumeActionDuplicateIntervalNanoseconds: UInt64 = 100_000_000,
        targetOverlayPresenter: any TargetOverlayPresenting = InactiveTargetOverlayPresenter(),
        mediaTargetSessionFactory: @escaping (RelayConfiguration?) -> MediaTargetSession? = {
            MediaTargetSessionFactory.make(configuration: $0)
        },
        remoteControl: RemoteControlModel? = nil
    ) {
        let gestureMonitor = VolumeKeyGestureMonitor()
        let configuration = configurationStore.load()
        self.volumeKeyGestureMonitor = gestureMonitor
        self.routeObserver = routeObserver
        self.networkPathObserver = networkPathObserver
        self.configurationStore = configurationStore
        self.volumeKeyMonitor = volumeKeyMonitor
        self.inputMonitoringAccess = inputMonitoringAccess
        self.accessibilityAccess = accessibilityAccess
        self.launchAtLoginClient = launchAtLoginClient
        self.volumeKeySuppressionTiming = volumeKeySuppressionTiming
        self.monotonicTimeProvider = monotonicTimeProvider
        self.externalVolumeActionDuplicateIntervalNanoseconds =
            externalVolumeActionDuplicateIntervalNanoseconds
        volumeKeyMonitor.setSuppressionTiming(volumeKeySuppressionTiming)
        self.targetOverlayPresenter = targetOverlayPresenter
        self.discovery = discovery
        self.remoteControl = remoteControl
        self.mediaTargetSessionFactory = mediaTargetSessionFactory
        self.preferences = configurationStore.defaults
        self.targetPresentation = MediaTargetPresentationModel(
            timing: targetPresentationTiming
        )
        self.coordinator = RelayCoordinator(
            configuration: configuration,
            cancelHeldGesture: {
                gestureMonitor.cancel()
            }
        )
        self.mediaTargetSession = mediaTargetSessionFactory(configuration)
        targetConfiguration = coordinator.configuration
        relayState = coordinator.relayState
        syncTargetOverlay()

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
                self.handleVolumeAction(
                    action,
                    isHeldRepeat: volumeKeyGestureMonitor.isRepeating(action)
                )
            }
        }
        routeObserver.onSnapshot = { [weak self] snapshot in
            guard let self else {
                return
            }
            let previousActivationMatches = activationMatches
            routeSnapshot = snapshot
            apply(.routeSnapshot(snapshot))
            if RelayConfigurationFactory.preview(for: snapshot) != nil {
                discovery.reportRouteAvailable()
            }
            guard !awaitingWakeCompletion else {
                return
            }
            if activationMatches != previousActivationMatches {
                refreshTargetSession(
                    invalidation: .routeContextChanged,
                    presentationInvalidation: activationMatches ? .session : .routeMismatch
                )
            } else {
                startTargetProbeIfNeeded()
            }
        }
        routeObserver.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            awaitingWakeCompletion = routeObservationState == .suspended && state == .observing
            cancelTargetProbe()
            routeObservationState = state
            apply(.routeObservationState(state))
        }
        routeObserver.onSleep = { [weak self] in
            guard let self else { return }
            volumeKeyGestureMonitor.cancel()
            discovery.cancelScan()
            refreshTargetSession(
                invalidation: .lifecycleChanged,
                presentationInvalidation: .sleep
            )
        }
        routeObserver.onWake = { [weak self] in
            guard let self else { return }
            awaitingWakeCompletion = false
            refreshTargetSession(
                invalidation: .lifecycleChanged,
                presentationInvalidation: .session
            )
        }
        networkPathObserver.onSnapshot = { [weak self] snapshot in
            self?.handleNetworkPathSnapshot(snapshot)
        }
        applicationActivationToken = applicationNotificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.networkPathObserver.refresh()
                self?.resolveAccessibilityAuthorization()
                self?.refreshInputMonitoring()
                self?.refreshLaunchAtLogin()
            }
        }
        applicationTerminationToken = applicationNotificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }
        routeObserver.start()
        networkPathObserver.start()
        resolveAccessibilityAuthorization()
        refreshInputMonitoring()
        refreshLaunchAtLogin()
        refreshTransportState()
        remoteControl?.startIfNeeded()
    }

    var launchAtLogin: Bool {
        launchAtLoginState.isEnabled
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

    var menuBarAccessibilityLabel: String {
        let status = "Media Control Relay, \(statusCopy.title)"
        guard let accessibleTargetStatus else {
            return status
        }
        return "\(status), \(accessibleTargetStatus)"
    }

    var targetControlsEnabled: Bool {
        relayState == .active
    }

    var configuredDeviceName: String {
        targetConfiguration?.target.name ?? "No target selected"
    }

    var selectedPreviewRouteDescription: String {
        guard let configuration = targetConfiguration else {
            return "No route selected"
        }
        let displayRequirement = configuration.activationRule.requiresDisplay
            ? "display required"
            : "audio-only matching"
        return "Audio: \(configuration.activationRule.audioOutputMatch) (\(displayRequirement))"
    }

    var canCreatePreviewTarget: Bool {
        RelayConfigurationFactory.preview(for: routeSnapshot) != nil
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
            "accessibility": accessibilityDiagnosticName,
            "volume_key_suppression": volumeKeySuppressionMode == .conditional
                ? "conditional"
                : "listen-only",
            "macos_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "product_status": "preview",
            "setup_complete": targetConfiguration == nil ? "no" : "yes",
            "target_kind": targetConfiguration?.target.kind.rawValue ?? "unconfigured",
            "activation": targetConfiguration == nil
                ? "unconfigured"
                : activationMatches ? "match" : "no-match",
            "commands_recorded": commandsRecorded.formatted(),
            "actions_not_recorded": commandsSuppressed.formatted(),
            "target_commands_dispatched": targetCommandsDispatched.formatted(),
            "target_commands_failed": targetCommandsFailed.formatted(),
            "target_recovery_attempts": targetRecoveryAttempts.formatted(),
            "volume_actions_emitted": observedVolumeActionCount.formatted(),
            "volume_events_observed": observedVolumeKeyEventCount.formatted(),
            "external_actions_accepted": externalVolumeActionsAccepted.formatted(),
            "external_actions_rejected": externalVolumeActionsRejected.formatted(),
            "external_actions_rate_limited": externalVolumeActionsRateLimited.formatted(),
            "remote_actions_rejected": externalRemoteActionsRejected.formatted(),
            "remote_actions_unavailable": externalRemoteActionsUnavailable.formatted(),
            "target_connection": targetConnectionDiagnosticName,
            "network_path": networkPathSnapshot.status.rawValue,
            "network_transitions": networkTransitionCount.formatted(),
        ].merging(routeDiagnostics) { current, _ in current }
        .merging(remoteControl?.diagnosticsFields ?? [:]) { _, remote in remote }
        var allowedFieldNames: Set<String> = [
            "app_version",
            "relay_state",
            "input_monitoring",
            "accessibility",
            "volume_key_suppression",
            "macos_version",
            "product_status",
            "setup_complete",
            "target_kind",
            "activation",
            "commands_recorded",
            "actions_not_recorded",
            "target_commands_dispatched",
            "target_commands_failed",
            "target_recovery_attempts",
            "volume_actions_emitted",
            "volume_events_observed",
            "external_actions_accepted",
            "external_actions_rejected",
            "external_actions_rate_limited",
            "target_connection",
            "network_path",
            "network_transitions",
            "route_observation",
            "audio_transport",
            "active_displays",
        ]
        allowedFieldNames.formUnion(RemoteControlModel.diagnosticFieldNames)
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
        cancelTargetProbe()
        let previousSession = mediaTargetSession
        mediaTargetSession = mediaTargetSessionFactory(configuration)
        apply(.configuration(configuration))
        apply(.transportReachability(.reachable))
        Task { await previousSession?.invalidate(.sessionReplaced) }
    }

    func selectDiscoveredTarget(_ choice: MediaTargetDiscoveryChoice) {
        let identity = MediaTargetIdentity(stableIdentifier: choice.id)
        guard let configuration = RelayConfigurationFactory.upnpMediaRenderer(
            identity: identity,
            for: routeSnapshot
        ) else {
            discovery.reportRouteUnavailable()
            return
        }

        configurationStore.save(configuration)
        let previousSession = mediaTargetSession
        cancelTargetProbe()
        mediaTargetSession = mediaTargetSessionFactory(configuration)
        apply(.configuration(configuration))
        refreshTransportState()
        discovery.cancelScan()
        Task { await previousSession?.invalidate(.sessionReplaced) }
    }

    func removeConfiguredTarget() {
        configurationStore.remove()
        let previousSession = mediaTargetSession
        cancelTargetProbe()
        mediaTargetSession = nil
        apply(.configuration(nil))
        discovery.cancelScan()
        Task { await previousSession?.invalidate(.sessionReplaced) }
    }

    func requestInputMonitoring() {
        preferences.set(true, forKey: inputMonitoringRequestedKey)
        requestedInputMonitoringThisLaunch = true
        inputMonitoringAccess.request()
        refreshInputMonitoring()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let operation: LaunchAtLoginOperation = enabled ? .register : .unregister
        launchAtLoginOperationFailure = nil
        do {
            if enabled {
                try launchAtLoginClient.register()
            } else {
                try launchAtLoginClient.unregister()
            }
        } catch {
            launchAtLoginOperationFailure = operation
        }
        readLaunchAtLoginStatus()
    }

    func refreshLaunchAtLogin() {
        launchAtLoginOperationFailure = nil
        readLaunchAtLoginStatus()
    }

    private func readLaunchAtLoginStatus() {
        launchAtLoginState = launchAtLoginClient.status()
    }

    func openLaunchAtLoginSettings() {
        launchAtLoginClient.openSystemSettingsLoginItems()
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func shutdown() {
        volumeKeyMonitor.revokeSuppressionAuthority()
        volumeKeyMonitor.stop()
        volumeKeySuppressionMode = .listenOnly
        volumeKeyGestureMonitor.cancel()
        cancelTargetProbe()
        discovery.cancelScan()
        routeObserver.stop()
        networkPathObserver.stop()
        volumeKeyTask?.cancel()
        volumeKeyTask = nil
        volumeActionTask?.cancel()
        volumeActionTask = nil
        remoteControl?.shutdown()
    }

    func handleExternalRemoteAction(_ action: MediaRemoteAction) {
        guard let remoteControl else {
            externalRemoteActionsUnavailable += 1
            return
        }
        remoteControl.handle(action)
    }

    func recordRejectedExternalRemoteURL(count: Int = 1) {
        let count = max(0, count)
        guard let remoteControl else {
            externalRemoteActionsRejected += count
            return
        }
        for _ in 0..<count {
            remoteControl.recordRejectedAction()
        }
    }

    var remoteControlTerminationStopper: (@Sendable () -> Void)? {
        remoteControl?.terminationStopper
    }

    func openInputMonitoringSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    func requestAccessibility() {
        preferences.set(true, forKey: accessibilityRequestedKey)
        requestedAccessibilityThisLaunch = true
        accessibilityAccess.request()
        refreshAccessibility()
    }

    func openAccessibilitySettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func openLocalNetworkSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
            fallback: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    func retryTargetConnection() {
        guard targetConfiguration?.target.kind == .upnpMediaRenderer else {
            return
        }
        targetRecoveryAttempts += 1
        let previousSnapshot = networkPathSnapshot
        networkPathObserver.refresh()
        if networkPathSnapshot == previousSnapshot {
            refreshTargetSession(invalidation: .networkContextChanged)
        }
    }

    private func openSystemSettings(
        _ primary: String,
        fallback: String? = nil
    ) {
        if let url = URL(string: primary), NSWorkspace.shared.open(url) {
            return
        }
        if let fallback,
           let url = URL(string: fallback) {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshInputMonitoring() {
        let previousAuthorization = inputMonitoringAuthorization
        inputMonitoringAuthorization = InputMonitoringDecision.resolve(
            preflightGranted: inputMonitoringAccess.preflight(),
            hasRequestedAccess: preferences.bool(
                forKey: inputMonitoringRequestedKey
            ),
            requestedThisLaunch: requestedInputMonitoringThisLaunch
        )
        apply(.inputMonitoringAuthorization(inputMonitoringAuthorization))
        if inputMonitoringAuthorization != previousAuthorization {
            refreshTargetSession(invalidation: .authorizationChanged)
        } else {
            startTargetProbeIfNeeded()
        }

        refreshVolumeKeyMonitor()
    }

    func refreshAccessibility() {
        resolveAccessibilityAuthorization()
        refreshVolumeKeyMonitor()
    }

    @discardableResult
    private func resolveAccessibilityAuthorization() -> Bool {
        let previousAuthorization = accessibilityAuthorization
        let preflightGranted = accessibilityAccess.preflight()
        if preflightGranted {
            preferences.set(true, forKey: accessibilityRequestedKey)
        }
        accessibilityAuthorization = AccessibilityDecision.resolve(
            preflightGranted: preflightGranted,
            hasRequestedAccess: preferences.bool(forKey: accessibilityRequestedKey),
            requestedThisLaunch: requestedAccessibilityThisLaunch
        )
        return accessibilityAuthorization != previousAuthorization
    }

    private func refreshVolumeKeyMonitor() {
        guard inputMonitoringAuthorization == .granted else {
            volumeKeyMonitor.revokeSuppressionAuthority()
            volumeKeyMonitor.stop()
            volumeKeySuppressionMode = .listenOnly
            volumeKeyGestureMonitor.cancel()
            inputMonitoringUnavailable = false
            return
        }

        let preferredMode: VolumeKeySuppressionMode =
            accessibilityAuthorization == .granted ? .conditional : .listenOnly
        volumeKeyMonitor.setSuppressionMode(preferredMode)
        do {
            try volumeKeyMonitor.start()
            volumeKeySuppressionMode = volumeKeyMonitor.suppressionMode
            inputMonitoringUnavailable = false
            syncVolumeKeySuppressionAuthority()
            if volumeKeySuppressionMode == .conditional,
               relayState == .active,
               let mediaTargetSession,
               commandContinuation != nil,
               commandPumpTask != nil {
                let targetAge = targetPresentation.lastConfirmationTimestamp.map {
                    presentationTimestamp - $0
                }
                let needsImmediateKeepalive = targetAge.map {
                    $0 > volumeKeySuppressionTiming.targetFreshness
                } ?? true
                scheduleTargetKeepalive(
                    for: mediaTargetSession,
                    immediate: needsImmediateKeepalive
                )
            }
        } catch {
            volumeKeyMonitor.revokeSuppressionAuthority()
            volumeKeySuppressionMode = .listenOnly
            inputMonitoringUnavailable = true
            inputMonitoringAuthorization = .denied
            apply(.inputMonitoringAuthorization(.denied))
            cancelTargetProbe()
            refreshTransportState()
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

    var accessibilityTitle: LocalizedStringResource {
        switch accessibilityAuthorization {
        case .notDetermined: return "Native HUD replacement is not set up"
        case .requested: return "Native HUD replacement needs a restart"
        case .denied: return "Native HUD replacement needs attention"
        case .granted:
            return volumeKeySuppressionMode == .conditional
                ? "Native HUD replacement is ready"
                : "Native HUD replacement is unavailable"
        }
    }

    var accessibilityDetail: LocalizedStringResource {
        switch accessibilityAuthorization {
        case .notDetermined:
            return "Allow Accessibility access to hide the Mac volume HUD only while the confirmed media target is ready."
        case .requested:
            return "Quit and reopen Media Control Relay to apply your choice."
        case .denied:
            return "Turn on Accessibility access in Privacy & Security. Until then, normal Mac handling remains enabled."
        case .granted:
            return volumeKeySuppressionMode == .conditional
                ? "The Mac volume HUD is replaced only for fresh, matched, healthy target commands."
                : "Volume keys remain pass-through because active filtering could not start."
        }
    }

    var accessibilitySystemImage: String {
        switch accessibilityAuthorization {
        case .notDetermined: return "rectangle.on.rectangle.slash"
        case .requested: return "arrow.clockwise.circle"
        case .denied: return "hand.raised.slash"
        case .granted:
            return volumeKeySuppressionMode == .conditional
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle"
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

    private var accessibilityDiagnosticName: String {
        switch accessibilityAuthorization {
        case .notDetermined: return "not-determined"
        case .requested: return "requested"
        case .denied: return "denied"
        case .granted: return "granted"
        }
    }

    var targetConnectionDiagnosticName: String {
        switch targetConfiguration?.target.kind {
        case .preview: "preview-sink"
        case .upnpMediaRenderer: "local-network"
        case nil: "not-available"
        }
    }

    private func handleNetworkPathSnapshot(_ snapshot: NetworkPathSnapshot) {
        guard snapshot != networkPathSnapshot else {
            return
        }

        let isInitialSnapshot = !hasReceivedNetworkPathSnapshot
        networkPathSnapshot = snapshot
        hasReceivedNetworkPathSnapshot = true
        if !isInitialSnapshot {
            networkTransitionCount += 1
            discovery.cancelScan()
        }

        guard targetConfiguration?.target.kind == .upnpMediaRenderer else {
            return
        }
        guard !isInitialSnapshot || snapshot.status == .unavailable ||
            snapshot.status == .localNetworkDenied else {
            return
        }
        guard !awaitingWakeCompletion,
              routeObservationState == .observing else {
            return
        }
        refreshTargetSession(invalidation: .networkContextChanged)
    }

    @discardableResult
    private func apply(_ event: RelayRoutingEvent) -> RelayCommand? {
        let command = coordinator.apply(event)
        syncCoordinatorState()
        switch event {
        case .configuration:
            invalidateTargetPresentation(.configuration)
        case let .inputMonitoringAuthorization(authorization)
            where authorization != .granted:
            invalidateTargetPresentation(.permission)
        case let .routeObservationState(state) where state != .observing:
            invalidateTargetPresentation(
                state == .suspended ? .sleep : .routeMismatch
            )
        default:
            break
        }
        return command
    }

    private func syncCoordinatorState() {
        let previousRelayState = relayState
        relayState = coordinator.relayState
        activationMatches = coordinator.activationMatches
        commandsRecorded = coordinator.recordedCommandCount
        commandsSuppressed = coordinator.suppressedCommandCount
        targetConfiguration = coordinator.configuration
        if previousRelayState == .active,
           relayState != .active,
           accessibleTargetStatus != String(localized: "Volume control unavailable") {
            accessibleTargetStatus = nil
        }
        syncTargetOverlay()
        syncVolumeKeySuppressionAuthority()
    }

    private func syncVolumeKeySuppressionAuthority() {
        volumeKeySuppressionMode = volumeKeyMonitor.suppressionMode
        let timestamp = presentationTimestamp
        let maximumTargetAge = volumeKeySuppressionTiming.targetFreshness
        let confirmedTargetAge = targetPresentation.lastConfirmationTimestamp.map {
            timestamp - $0
        }
        let inputs = VolumeKeySuppressionReadinessInputs(
            relayState: relayState,
            routeObservationIsFresh: routeObservationState == .observing && activationMatches,
            inputMonitoringGranted: inputMonitoringAuthorization == .granted,
            accessibilityGranted: accessibilityAuthorization == .granted,
            dispatchReady: commandContinuation != nil && commandPumpTask != nil,
            sessionReady: mediaTargetSession != nil,
            awaitingWakeCompletion: awaitingWakeCompletion,
            confirmedTargetAge: confirmedTargetAge,
            maximumTargetAge: maximumTargetAge
        )
        guard volumeKeySuppressionMode == .conditional,
              VolumeKeySuppressionPolicy.isArmed(inputs),
              let confirmedTargetAge else {
            volumeKeyMonitor.revokeSuppressionAuthority()
            return
        }

        volumeKeyMonitor.updateSuppressionAuthority(
            VolumeKeySuppressionAuthority(
                issuedAt: timestamp,
                validFor: maximumTargetAge - confirmedTargetAge,
                isArmed: true
            )
        )
    }

    private func refreshTransportState() {
        switch targetConfiguration?.target.kind {
        case .preview:
            apply(.transportReachability(.reachable))
        case .upnpMediaRenderer:
            if mediaTargetSession == nil {
                apply(.transportReachability(.unreachable))
            } else {
                switch networkPathSnapshot.status {
                case .localNetworkDenied:
                    apply(.transportReachability(.localNetworkDenied))
                case .unavailable:
                    apply(.transportReachability(.unreachable))
                case .unknown, .available:
                    apply(.transportReachability(.unknown))
                    startTargetProbeIfNeeded()
                }
            }
        case nil:
            apply(.transportReachability(.unknown))
        }
    }

    private func refreshTargetSession(
        invalidation: MediaTargetSessionInvalidation,
        presentationInvalidation: MediaTargetPresentationInvalidation? = nil
    ) {
        cancelTargetProbe()
        if let presentationInvalidation {
            invalidateTargetPresentation(presentationInvalidation)
        } else {
            invalidateTargetPresentation(for: invalidation)
        }

        guard targetConfiguration?.target.kind == .upnpMediaRenderer else {
            return
        }
        guard let mediaTargetSession else {
            apply(.transportReachability(.unreachable))
            return
        }

        switch networkPathSnapshot.status {
        case .localNetworkDenied:
            apply(.transportReachability(.localNetworkDenied))
            startTargetInvalidation(mediaTargetSession, invalidation: invalidation)
        case .unavailable:
            apply(.transportReachability(.unreachable))
            startTargetInvalidation(mediaTargetSession, invalidation: invalidation)
        case .unknown, .available:
            apply(.transportReachability(.unknown))
            startTargetProbe(
                mediaTargetSession,
                invalidation: invalidation
            )
        }
    }

    private func startTargetProbeIfNeeded() {
        guard targetProbeTask == nil,
              targetConfiguration?.target.kind == .upnpMediaRenderer,
              networkPathSnapshot.status == .unknown ||
                networkPathSnapshot.status == .available,
              relayState == .checkingTarget ||
                relayState == .offline ||
                relayState == .needsLocalNetworkPermission else {
            return
        }
        guard let mediaTargetSession else {
            apply(.transportReachability(.unreachable))
            return
        }

        apply(.transportReachability(.unknown))
        startTargetProbe(mediaTargetSession, invalidation: nil)
    }

    private func startTargetProbe(
        _ mediaTargetSession: MediaTargetSession,
        invalidation: MediaTargetSessionInvalidation?
    ) {
        targetProbeGeneration &+= 1
        let generation = targetProbeGeneration
        let presentationEpoch = targetPresentation.invalidationEpoch
        targetProbeTask = Task { @MainActor [weak self, mediaTargetSession] in
            defer {
                if let self, self.targetProbeGeneration == generation {
                    self.targetProbeTask = nil
                }
            }

            if let invalidation {
                guard !Task.isCancelled else {
                    return
                }
                await mediaTargetSession.invalidate(
                    invalidation,
                    requestID: generation
                )
            }
            guard let self,
                  !Task.isCancelled,
                  targetProbeGeneration == generation,
                  self.mediaTargetSession === mediaTargetSession,
                  relayState == .checkingTarget else {
                return
            }
            guard let outcome = await mediaTargetSession.probe(),
                  !Task.isCancelled,
                  targetProbeGeneration == generation,
                  self.mediaTargetSession === mediaTargetSession else {
                return
            }
            let reachability = effectiveReachability(outcome.reachability)
            if reachability == .reachable {
                let accepted = targetPresentation.receiveProbe(
                    outcome,
                    epoch: presentationEpoch,
                    at: presentationTimestamp
                )
                if accepted {
                    updateAccessibleTargetStatus(from: targetPresentation.confirmedValue)
                }
                syncPresentationState()
                startCommandDispatch(for: mediaTargetSession)
            } else {
                cancelCommandDispatch()
            }
            apply(.transportReachability(reachability))
            if reachability == .reachable {
                scheduleTargetKeepalive(for: mediaTargetSession)
            }
        }
    }

    private func startTargetInvalidation(
        _ mediaTargetSession: MediaTargetSession,
        invalidation: MediaTargetSessionInvalidation
    ) {
        targetProbeGeneration &+= 1
        let generation = targetProbeGeneration
        targetProbeTask = Task { @MainActor [weak self, mediaTargetSession] in
            await mediaTargetSession.invalidate(
                invalidation,
                requestID: generation
            )
            guard let self,
                  targetProbeGeneration == generation,
                  self.mediaTargetSession === mediaTargetSession else {
                return
            }
            targetProbeTask = nil
        }
    }

    private func cancelTargetProbe() {
        targetProbeGeneration &+= 1
        targetProbeTask?.cancel()
        targetProbeTask = nil
        cancelCommandDispatch()
    }

    private func scheduleTargetKeepalive(
        for mediaTargetSession: MediaTargetSession,
        immediate: Bool = false
    ) {
        cancelTargetKeepalive()
        guard volumeKeySuppressionMode == .conditional,
              inputMonitoringAuthorization == .granted,
              accessibilityAuthorization == .granted,
              volumeKeySuppressionTiming.targetFreshness > 0,
              volumeKeySuppressionTiming.keepaliveInterval > 0 else {
            return
        }

        targetKeepaliveGeneration &+= 1
        let generation = targetKeepaliveGeneration
        targetKeepaliveTask = Task { @MainActor [weak self, mediaTargetSession] in
            defer {
                if let self, self.targetKeepaliveGeneration == generation {
                    self.targetKeepaliveTask = nil
                }
            }
            do {
                try await Task.sleep(
                    for: .seconds(
                        immediate ? 0 : self?.volumeKeySuppressionTiming.keepaliveInterval ?? 0
                    )
                )
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  targetKeepaliveGeneration == generation,
                  self.mediaTargetSession === mediaTargetSession,
                  relayState == .active,
                  commandContinuation != nil,
                  commandPumpTask != nil,
                  activePresentationRequest == nil else {
                return
            }

            let presentationEpoch = targetPresentation.invalidationEpoch
            guard let outcome = await mediaTargetSession.probe(),
                  !Task.isCancelled,
                  targetKeepaliveGeneration == generation,
                  self.mediaTargetSession === mediaTargetSession else {
                return
            }

            targetKeepaliveTask = nil
            let reachability = effectiveReachability(outcome.reachability)
            if reachability == .reachable {
                let accepted = targetPresentation.receiveProbe(
                    outcome,
                    epoch: presentationEpoch,
                    at: presentationTimestamp
                )
                if accepted {
                    updateAccessibleTargetStatus(from: targetPresentation.confirmedValue)
                }
                syncPresentationState()
            }
            apply(.transportReachability(reachability))
            if reachability == .reachable {
                scheduleTargetKeepalive(for: mediaTargetSession)
            } else {
                cancelCommandDispatch()
            }
        }
    }

    private func cancelTargetKeepalive() {
        targetKeepaliveGeneration &+= 1
        targetKeepaliveTask?.cancel()
        targetKeepaliveTask = nil
    }

    private func startCommandDispatch(for mediaTargetSession: MediaTargetSession) {
        cancelCommandDispatch()
        let stream = AsyncStream<TargetCommandRequest>.makeStream()
        commandGeneration &+= 1
        let generation = commandGeneration
        commandContinuation = stream.continuation
        commandPumpTask = Task { @MainActor [weak self, mediaTargetSession] in
            defer {
                if let self, self.commandGeneration == generation {
                    self.commandContinuation = nil
                    self.commandPumpTask = nil
                }
            }

            for await request in stream.stream {
                guard let self,
                      !Task.isCancelled,
                      commandGeneration == generation,
                      self.mediaTargetSession === mediaTargetSession else {
                    return
                }
                guard request.holdGeneration == nil ||
                    request.holdGeneration == activeHoldGeneration else {
                    coordinator.completeCommand()
                    syncCoordinatorState()
                    scheduleTargetKeepalive(for: mediaTargetSession)
                    continue
                }
                targetCommandsDispatched += 1
                let presentationRequest = beginPresentation(for: request.command.action)
                let outcome = await mediaTargetSession.execute(request.command.action)
                guard !Task.isCancelled,
                      commandGeneration == generation,
                      self.mediaTargetSession === mediaTargetSession else {
                    return
                }

                coordinator.completeCommand()
                syncCoordinatorState()
                guard let outcome else {
                    cancelPresentationRequest(presentationRequest)
                    scheduleTargetKeepalive(for: mediaTargetSession)
                    continue
                }
                receivePresentationOutcome(outcome, for: presentationRequest)
                let reachability = effectiveReachability(outcome.reachability)
                if reachability != .reachable {
                    targetCommandsFailed += 1
                }
                apply(.transportReachability(reachability))
                if reachability != .reachable {
                    cancelCommandDispatch()
                    return
                }
                scheduleTargetKeepalive(for: mediaTargetSession)
            }
        }
    }

    private func cancelCommandDispatch() {
        cancelTargetKeepalive()
        commandGeneration &+= 1
        commandContinuation?.finish()
        commandContinuation = nil
        commandPumpTask?.cancel()
        commandPumpTask = nil
        coordinator.cancelPendingCommands()
        syncCoordinatorState()
        cancelActivePresentationRequest()
    }

    private func effectiveReachability(
        _ reachability: TransportReachability
    ) -> TransportReachability {
        guard reachability == .localNetworkDenied else {
            return reachability
        }
        return switch networkPathSnapshot.status {
        case .unknown, .available, .localNetworkDenied:
            .localNetworkDenied
        case .unavailable:
            .unreachable
        }
    }

    private func record(_ event: VolumeKeyEvent) {
        observedVolumeKeyEventCount += 1
        if event.phase == .pressed, !event.isRepeat {
            observedVolumeKeyPressCount += 1
        }
        if event.phase == .pressed,
            event.isRepeat,
           event.action.supportsHoldRepeat {
            if repeatedVolumeAction != event.action {
                activeHoldGeneration &+= 1
            }
            repeatedVolumeAction = event.action
        }
        volumeKeyGestureMonitor.ingest(event)
        if event.phase == .released,
           repeatedVolumeAction == event.action {
            repeatedVolumeAction = nil
            activeHoldGeneration &+= 1
        }
    }

    func handleVolumeAction(
        _ action: VolumeAction,
        isHeldRepeat: Bool = false
    ) {
        dispatchVolumeAction(
            action,
            isHeldRepeat: isHeldRepeat,
            recordAsObservedInput: true
        )
    }

    func handleMenuVolumeAction(_ action: VolumeAction) {
        dispatchVolumeAction(
            action,
            isHeldRepeat: false,
            recordAsObservedInput: false
        )
    }

    func handleExternalVolumeAction(_ action: VolumeAction) {
        let timestamp = monotonicTimeProvider.now()
        if let lastExternalVolumeAction,
           lastExternalVolumeAction.action == action,
           timestamp >= lastExternalVolumeAction.timestamp,
           timestamp - lastExternalVolumeAction.timestamp
                < externalVolumeActionDuplicateIntervalNanoseconds {
            externalVolumeActionsRateLimited += 1
            return
        }

        externalVolumeActionsAccepted += 1
        lastExternalVolumeAction = (action, timestamp)
        dispatchVolumeAction(
            action,
            isHeldRepeat: false,
            recordAsObservedInput: false
        )
    }

    func recordRejectedExternalVolumeURL(count: Int = 1) {
        externalVolumeActionsRejected += max(0, count)
    }

    private func dispatchVolumeAction(
        _ action: VolumeAction,
        isHeldRepeat: Bool,
        recordAsObservedInput: Bool
    ) {
        if recordAsObservedInput {
            observedVolumeActionCount += 1
            lastObservedVolumeAction = action
        }
        guard let command = apply(.volumeAction(action)) else {
            return
        }

        switch targetConfiguration?.target.kind {
        case .preview:
            coordinator.completeCommand()
            syncCoordinatorState()
        case .upnpMediaRenderer:
            cancelTargetKeepalive()
            if isHeldRepeat,
               repeatedVolumeAction != action {
                activeHoldGeneration &+= 1
                repeatedVolumeAction = action
            }
            let holdGeneration = isHeldRepeat ? activeHoldGeneration : nil
            guard let commandContinuation else {
                failCommandDispatch()
                return
            }
            let request = TargetCommandRequest(
                command: command,
                holdGeneration: holdGeneration
            )
            switch commandContinuation.yield(request) {
            case .enqueued:
                break
            case .dropped, .terminated:
                failCommandDispatch()
            @unknown default:
                failCommandDispatch()
            }
        case nil:
            coordinator.completeCommand()
            syncCoordinatorState()
        }
    }

    private var presentationTimestamp: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func beginPresentation(for action: VolumeAction) -> PendingPresentationRequest {
        nextPresentationRequestID &+= 1
        let request = PendingPresentationRequest(
            requestID: nextPresentationRequestID,
            epoch: targetPresentation.invalidationEpoch
        )
        _ = targetPresentation.begin(
            action: action,
            requestID: request.requestID,
            epoch: request.epoch,
            at: presentationTimestamp
        )
        activePresentationRequest = request
        syncPresentationState()
        return request
    }

    private func receivePresentationOutcome(
        _ outcome: MediaTargetSessionOutcome,
        for request: PendingPresentationRequest
    ) {
        guard activePresentationRequest == request else {
            return
        }
        _ = targetPresentation.receive(
            outcome,
            requestID: request.requestID,
            epoch: request.epoch,
            at: presentationTimestamp
        )
        activePresentationRequest = nil
        syncPresentationState()
    }

    private func cancelPresentationRequest(_ request: PendingPresentationRequest) {
        guard activePresentationRequest == request else {
            return
        }
        _ = targetPresentation.cancel(
            requestID: request.requestID,
            epoch: request.epoch
        )
        activePresentationRequest = nil
        syncPresentationState()
    }

    private func cancelActivePresentationRequest() {
        guard let activePresentationRequest else {
            return
        }
        cancelPresentationRequest(activePresentationRequest)
    }

    private func failCommandDispatch() {
        coordinator.completeCommand()
        syncCoordinatorState()
        apply(.transportReachability(.unreachable))
        cancelCommandDispatch()
    }

    private func invalidateTargetPresentation(
        _ reason: MediaTargetPresentationInvalidation
    ) {
        targetPresentation.invalidate(reason)
        activePresentationRequest = nil
        accessibleTargetStatus = nil
        syncPresentationState()
    }

    private func invalidateTargetPresentation(
        for reason: MediaTargetSessionInvalidation
    ) {
        switch reason {
        case .authorizationChanged:
            invalidateTargetPresentation(.session)
        case .routeContextChanged:
            invalidateTargetPresentation(.routeMismatch)
        case .networkContextChanged:
            invalidateTargetPresentation(.session)
        case .lifecycleChanged:
            invalidateTargetPresentation(.sleep)
        case .sessionReplaced:
            invalidateTargetPresentation(.session)
        }
    }

    private func syncPresentationState() {
        let state = targetPresentation.state
        guard targetPresentationState != state else {
            return
        }
        targetPresentationState = state
        syncTargetOverlay()
        schedulePresentationDismissal()
        publishAccessibilityStatusIfNeeded()
        scheduleAccessibilityStatusPublication()
    }

    private func syncTargetOverlay() {
        targetOverlayPresenter.update(
            presentationState: targetPresentationState,
            routeSnapshot: routeSnapshot,
            activationRule: targetConfiguration?.activationRule
        )
    }

    private func schedulePresentationDismissal() {
        presentationDismissalTask?.cancel()
        guard targetPresentationState.isVisible else {
            presentationDismissalTask = nil
            return
        }

        let delay = targetPresentation.timing.confirmationDisplayDuration
        presentationDismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else {
                return
            }
            _ = targetPresentation.advance(to: presentationTimestamp)
            syncPresentationState()
        }
    }

    private func publishAccessibilityStatusIfNeeded() {
        if targetPresentation.shouldAnnounceFailure() {
            publishAccessibilityStatus(String(localized: "Volume control unavailable"))
            return
        }

        guard let value = targetPresentationState.value else {
            return
        }

        let wasUnavailable = accessibleTargetStatus == String(localized: "Volume control unavailable")
        let shouldPublish = targetPresentation.shouldAnnounce(at: presentationTimestamp)
        if shouldPublish || wasUnavailable {
            publishAccessibilityStatus(accessibilityStatus(for: value))
        }
    }

    private func publishAccessibilityStatus(_ status: String) {
        guard accessibleTargetStatus != status else {
            return
        }
        accessibleTargetStatus = status
    }

    private func updateAccessibleTargetStatus(from value: MediaTargetPresentationValue?) {
        guard let value else {
            return
        }
        publishAccessibilityStatus(accessibilityStatus(for: value))
    }

    private func accessibilityStatus(for value: MediaTargetPresentationValue) -> String {
        value.isMuted
            ? String(localized: "Muted")
            : String(localized: "Volume \(value.percentage) percent")
    }

    private func scheduleAccessibilityStatusPublication() {
        accessibilityStatusPublicationGeneration &+= 1
        accessibilityStatusPublicationTask?.cancel()
        guard let deadline = targetPresentation.pendingAnnouncementDeadline else {
            accessibilityStatusPublicationTask = nil
            return
        }

        let generation = accessibilityStatusPublicationGeneration
        let delay = max(0, deadline - presentationTimestamp)
        accessibilityStatusPublicationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  accessibilityStatusPublicationGeneration == generation else {
                return
            }
            accessibilityStatusPublicationTask = nil
            publishAccessibilityStatusIfNeeded()
            scheduleAccessibilityStatusPublication()
        }
    }
}

extension RelayState {
    var diagnosticName: String {
        switch self {
        case .unconfigured: "unconfigured"
        case .unsupported: "unsupported"
        case .needsPermission: "needs-permission"
        case .needsLocalNetworkPermission: "needs-local-network-permission"
        case .targetAuthenticationRejected: "target-authentication-rejected"
        case .dormant: "dormant"
        case .checkingTarget: "checking-target"
        case .offline: "offline"
        case .active: "active"
        }
    }
}
