import Foundation

public struct RelayCommand: Equatable, Sendable {
    public let sequence: Int
    public let action: VolumeAction

    public init(sequence: Int, action: VolumeAction) {
        self.sequence = sequence
        self.action = action
    }
}

public enum RelayRoutingEvent: Equatable, Sendable {
    case configuration(RelayConfiguration?)
    case inputMonitoringAuthorization(InputMonitoringAuthorization)
    case routeSnapshot(RouteSnapshot)
    case routeObservationState(RouteObservationState)
    case transportReachability(TransportReachability)
    case volumeAction(VolumeAction)
}

public struct RelayRoutingOutput: Equatable, Sendable {
    public let resolvedState: RelayState
    public let command: RelayCommand?
    public let cancelHeldGesture: Bool
    public let cancelPendingCommand: Bool
    public let activationMatches: Bool

    public init(
        resolvedState: RelayState,
        command: RelayCommand?,
        cancelHeldGesture: Bool,
        cancelPendingCommand: Bool,
        activationMatches: Bool
    ) {
        self.resolvedState = resolvedState
        self.command = command
        self.cancelHeldGesture = cancelHeldGesture
        self.cancelPendingCommand = cancelPendingCommand
        self.activationMatches = activationMatches
    }
}

public struct RelayRoutingReducer: Sendable {
    public private(set) var configuration: RelayConfiguration?
    public private(set) var inputMonitoringAuthorization: InputMonitoringAuthorization
    public private(set) var routeSnapshot: RouteSnapshot
    public private(set) var routeObservationState: RouteObservationState
    public private(set) var transportReachability: TransportReachability
    public private(set) var activationMatches = false

    private let policy: VolumeCommandQueuePolicy
    private var hasCurrentRouteSnapshot = false
    private var nextCommandSequence = 1
    private var resolvedState: RelayState

    public init(
        configuration: RelayConfiguration? = nil,
        inputMonitoringAuthorization: InputMonitoringAuthorization = .notDetermined,
        routeSnapshot: RouteSnapshot = RouteSnapshot(audioOutput: nil, displays: []),
        routeObservationState: RouteObservationState = .stopped,
        transportReachability: TransportReachability = .unknown,
        policy: VolumeCommandQueuePolicy = .default
    ) {
        self.configuration = configuration
        self.inputMonitoringAuthorization = inputMonitoringAuthorization
        self.routeSnapshot = routeSnapshot
        self.routeObservationState = routeObservationState
        self.transportReachability = transportReachability
        self.policy = policy
        self.resolvedState = .unconfigured
        self.activationMatches = false
        self.hasCurrentRouteSnapshot = false
        self.resolvedState = resolveState()
    }

    public var state: RelayState {
        resolvedState
    }

    @discardableResult
    public mutating func reduce(
        _ event: RelayRoutingEvent,
        pendingCommandCount: Int = 0
    ) -> RelayRoutingOutput {
        let previousState = resolvedState

        switch event {
        case let .configuration(configuration):
            self.configuration = configuration
            nextCommandSequence = 1
            if configuration == nil {
                activationMatches = false
            } else {
                refreshActivationMatch()
            }
        case let .inputMonitoringAuthorization(authorization):
            inputMonitoringAuthorization = authorization
        case let .routeSnapshot(snapshot):
            routeSnapshot = snapshot
            hasCurrentRouteSnapshot = routeObservationState == .observing
            refreshActivationMatch()
        case let .routeObservationState(state):
            routeObservationState = state
            hasCurrentRouteSnapshot = false
            refreshActivationMatch()
        case let .transportReachability(reachability):
            transportReachability = reachability
        case let .volumeAction(action):
            resolvedState = resolveState()
            let command: RelayCommand?
            if resolvedState == .active,
               policy.canEnqueue(pendingCount: pendingCommandCount) {
                command = RelayCommand(sequence: nextCommandSequence, action: action)
                nextCommandSequence += 1
            } else {
                command = nil
            }
            let transitionedOutOfActive = previousState == .active && resolvedState != .active
            return RelayRoutingOutput(
                resolvedState: resolvedState,
                command: command,
                cancelHeldGesture: transitionedOutOfActive,
                cancelPendingCommand: transitionedOutOfActive,
                activationMatches: activationMatches
            )
        }

        resolvedState = resolveState()
        let transitionedOutOfActive = previousState == .active && resolvedState != .active
        return RelayRoutingOutput(
            resolvedState: resolvedState,
            command: nil,
            cancelHeldGesture: transitionedOutOfActive,
            cancelPendingCommand: transitionedOutOfActive,
            activationMatches: activationMatches
        )
    }

    private mutating func refreshActivationMatch() {
        guard configuration != nil,
              routeObservationState == .observing,
              hasCurrentRouteSnapshot else {
            activationMatches = false
            return
        }
        activationMatches = configuration?.activationRule.matches(
            routeSnapshot.activationSnapshot
        ) ?? false
    }

    private func resolveState() -> RelayState {
        RelayStateResolver.resolve(
            RelayStateInputs(
                targetConfigured: configuration != nil,
                deviceSupported: configuration?.target.kind == .preview,
                inputMonitoringGranted: inputMonitoringAuthorization == .granted,
                activationMatches: activationMatches,
                transportReachability: transportReachability
            )
        )
    }
}
