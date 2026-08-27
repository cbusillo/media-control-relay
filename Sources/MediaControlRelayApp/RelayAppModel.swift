import AppKit
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
    var targetCommandsDispatched = 0
    var targetCommandsFailed = 0
    var targetRecoveryAttempts = 0
    var networkTransitionCount = 0
    var networkPathSnapshot = NetworkPathSnapshot.unknown
    var targetConfiguration: RelayConfiguration?
    private(set) var targetPresentationState: MediaTargetPresentationState = .hidden
    var presentationInvalidationEpoch: UInt64 { targetPresentation.invalidationEpoch }

    let productStatus: LocalizedStringResource = "Preview build"
    let discovery: MediaTargetDiscoveryModel

    private let volumeKeyMonitor: any VolumeKeyMonitoring
    private let volumeKeyGestureMonitor: VolumeKeyGestureMonitor
    private let routeObserver: any RouteObserving
    private let networkPathObserver: any NetworkPathObserving
    private let configurationStore: RelayConfigurationStore
    private let inputMonitoringAccess: InputMonitoringAccessClient
    private let mediaTargetSessionFactory: (RelayConfiguration?) -> MediaTargetSession?
    private let coordinator: RelayCoordinator
    private let preferences: UserDefaults
    private var mediaTargetSession: MediaTargetSession?
    private var targetPresentation: MediaTargetPresentationModel
    private var applicationActivationToken: NSObjectProtocol?
    private var volumeKeyTask: Task<Void, Never>?
    private var volumeActionTask: Task<Void, Never>?
    private var targetProbeTask: Task<Void, Never>?
    private var targetProbeGeneration: UInt64 = 0
    private var commandContinuation: AsyncStream<TargetCommandRequest>.Continuation?
    private var commandPumpTask: Task<Void, Never>?
    private var commandGeneration: UInt64 = 0
    private var nextPresentationRequestID: UInt64 = 0
    private var repeatedVolumeAction: VolumeAction?
    private var activeHoldGeneration: UInt64 = 0
    private var activePresentationRequest: PendingPresentationRequest?
    private var presentationDismissalTask: Task<Void, Never>?
    private var awaitingWakeCompletion = false
    private var hasReceivedNetworkPathSnapshot = false
    private let inputMonitoringRequestedKey = "inputMonitoringAccessRequested"
    private var requestedInputMonitoringThisLaunch = false
    private let postAccessibilityAnnouncement: (String) -> Void

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
        applicationNotificationCenter: NotificationCenter = .default,
        discovery: MediaTargetDiscoveryModel = MediaTargetDiscoveryModel(),
        targetPresentationTiming: MediaTargetPresentationTiming = MediaTargetPresentationTiming(),
        postAccessibilityAnnouncement: @escaping (String) -> Void = {
            NSAccessibility.post(
                element: NSApp,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: $0,
                    .priority: NSAccessibilityPriorityLevel.low.rawValue,
                ]
            )
        },
        mediaTargetSessionFactory: @escaping (RelayConfiguration?) -> MediaTargetSession? = {
            MediaTargetSessionFactory.make(configuration: $0)
        }
    ) {
        let gestureMonitor = VolumeKeyGestureMonitor()
        let configuration = configurationStore.load()
        self.volumeKeyGestureMonitor = gestureMonitor
        self.routeObserver = routeObserver
        self.networkPathObserver = networkPathObserver
        self.configurationStore = configurationStore
        self.volumeKeyMonitor = volumeKeyMonitor
        self.inputMonitoringAccess = inputMonitoringAccess
        self.discovery = discovery
        self.mediaTargetSessionFactory = mediaTargetSessionFactory
        self.preferences = configurationStore.defaults
        self.postAccessibilityAnnouncement = postAccessibilityAnnouncement
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
                self?.refreshInputMonitoring()
            }
        }
        routeObserver.start()
        networkPathObserver.start()
        refreshInputMonitoring()
        refreshTransportState()
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
            "target_connection": targetConnectionDiagnosticName,
            "network_path": networkPathSnapshot.status.rawValue,
            "network_transitions": networkTransitionCount.formatted(),
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
            "target_commands_dispatched",
            "target_commands_failed",
            "target_recovery_attempts",
            "volume_actions_emitted",
            "volume_events_observed",
            "target_connection",
            "network_path",
            "network_transitions",
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

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func openInputMonitoringSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
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
        relayState = coordinator.relayState
        activationMatches = coordinator.activationMatches
        commandsRecorded = coordinator.recordedCommandCount
        commandsSuppressed = coordinator.suppressedCommandCount
        targetConfiguration = coordinator.configuration
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
              relayState == .checkingTarget || relayState == .offline else {
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
            if outcome.reachability == .reachable {
                _ = targetPresentation.receiveProbe(
                    outcome,
                    epoch: presentationEpoch,
                    at: presentationTimestamp
                )
                syncPresentationState()
                startCommandDispatch(for: mediaTargetSession)
            } else {
                cancelCommandDispatch()
            }
            apply(.transportReachability(outcome.reachability))
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
                    continue
                }
                receivePresentationOutcome(outcome, for: presentationRequest)
                if outcome.reachability != .reachable {
                    targetCommandsFailed += 1
                }
                apply(.transportReachability(outcome.reachability))
                if outcome.reachability != .reachable {
                    cancelCommandDispatch()
                    return
                }
            }
        }
    }

    private func cancelCommandDispatch() {
        commandGeneration &+= 1
        commandContinuation?.finish()
        commandContinuation = nil
        commandPumpTask?.cancel()
        commandPumpTask = nil
        coordinator.cancelPendingCommands()
        syncCoordinatorState()
        cancelActivePresentationRequest()
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
        observedVolumeActionCount += 1
        lastObservedVolumeAction = action
        guard let command = apply(.volumeAction(action)) else {
            return
        }

        switch targetConfiguration?.target.kind {
        case .preview:
            coordinator.completeCommand()
            syncCoordinatorState()
        case .upnpMediaRenderer:
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
        Date().timeIntervalSinceReferenceDate
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
        schedulePresentationDismissal()
        announcePresentationIfNeeded()
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

    private func announcePresentationIfNeeded() {
        guard targetPresentation.shouldAnnounce(at: presentationTimestamp),
              let value = targetPresentationState.value else {
            return
        }

        let announcement = value.isMuted
            ? "Muted"
            : "Volume \(value.percentage) percent"
        postAccessibilityAnnouncement(announcement)
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
