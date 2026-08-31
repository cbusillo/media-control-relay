import Foundation

public enum VolumeKeySuppressionMode: Equatable, Sendable {
    case listenOnly
    case conditional
}

public struct VolumeKeySuppressionTiming: Equatable, Sendable {
    public let targetFreshness: TimeInterval
    public let keepaliveInterval: TimeInterval
    public let maximumLatchIdle: TimeInterval

    public init(
        targetFreshness: TimeInterval = 8,
        keepaliveInterval: TimeInterval = 5,
        maximumLatchIdle: TimeInterval = 1
    ) {
        self.targetFreshness = max(0, targetFreshness)
        self.keepaliveInterval = min(
            max(0, keepaliveInterval),
            self.targetFreshness
        )
        self.maximumLatchIdle = max(0, maximumLatchIdle)
    }

    public static let `default` = VolumeKeySuppressionTiming()
}

public struct VolumeKeySuppressionReadinessInputs: Equatable, Sendable {
    public let relayState: RelayState
    public let routeObservationIsFresh: Bool
    public let inputMonitoringGranted: Bool
    public let accessibilityGranted: Bool
    public let dispatchReady: Bool
    public let sessionReady: Bool
    public let awaitingWakeCompletion: Bool
    public let confirmedTargetAge: TimeInterval?
    public let maximumTargetAge: TimeInterval

    public init(
        relayState: RelayState,
        routeObservationIsFresh: Bool,
        inputMonitoringGranted: Bool,
        accessibilityGranted: Bool,
        dispatchReady: Bool,
        sessionReady: Bool,
        awaitingWakeCompletion: Bool,
        confirmedTargetAge: TimeInterval?,
        maximumTargetAge: TimeInterval
    ) {
        self.relayState = relayState
        self.routeObservationIsFresh = routeObservationIsFresh
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityGranted = accessibilityGranted
        self.dispatchReady = dispatchReady
        self.sessionReady = sessionReady
        self.awaitingWakeCompletion = awaitingWakeCompletion
        self.confirmedTargetAge = confirmedTargetAge
        self.maximumTargetAge = max(0, maximumTargetAge)
    }
}

public struct VolumeKeySuppressionAuthority: Equatable, Sendable {
    public let issuedAt: TimeInterval
    public let validFor: TimeInterval
    public let isArmed: Bool

    public init(
        issuedAt: TimeInterval,
        validFor: TimeInterval,
        isArmed: Bool
    ) {
        self.issuedAt = issuedAt
        self.validFor = max(0, validFor)
        self.isArmed = isArmed
    }

    public func isValid(at uptime: TimeInterval) -> Bool {
        isArmed &&
            uptime >= issuedAt &&
            uptime - issuedAt <= validFor
    }
}

public struct VolumeKeySuppressionState: Equatable, Sendable {
    public var latchedActions: [VolumeAction: TimeInterval]

    public init(latchedActions: [VolumeAction: TimeInterval] = [:]) {
        self.latchedActions = latchedActions
    }
}

public enum VolumeKeySuppressionDecision: Equatable, Sendable {
    case consume
    case passThrough
}

public struct VolumeKeySuppressionEvaluation: Equatable, Sendable {
    public let decision: VolumeKeySuppressionDecision
    public let state: VolumeKeySuppressionState

    public init(
        decision: VolumeKeySuppressionDecision,
        state: VolumeKeySuppressionState
    ) {
        self.decision = decision
        self.state = state
    }
}

public enum VolumeKeySuppressionPolicy {
    public static func isArmed(
        _ inputs: VolumeKeySuppressionReadinessInputs
    ) -> Bool {
        guard let confirmedTargetAge = inputs.confirmedTargetAge else {
            return false
        }

        return inputs.relayState == .active &&
            inputs.routeObservationIsFresh &&
            inputs.inputMonitoringGranted &&
            inputs.accessibilityGranted &&
            inputs.dispatchReady &&
            inputs.sessionReady &&
            !inputs.awaitingWakeCompletion &&
            confirmedTargetAge >= 0 &&
            confirmedTargetAge <= inputs.maximumTargetAge
    }

    public static func evaluate(
        event: VolumeKeyEvent,
        mode: VolumeKeySuppressionMode,
        authority: VolumeKeySuppressionAuthority?,
        state: VolumeKeySuppressionState,
        uptime: TimeInterval,
        maximumLatchIdle: TimeInterval = VolumeKeySuppressionTiming.default.maximumLatchIdle
    ) -> VolumeKeySuppressionEvaluation {
        var nextState = state
        let boundedLatchIdle = max(0, maximumLatchIdle)
        nextState.latchedActions = nextState.latchedActions.filter { _, lastEventAt in
            uptime >= lastEventAt && uptime - lastEventAt <= boundedLatchIdle
        }

        if event.phase == .released {
            guard nextState.latchedActions.removeValue(forKey: event.action) != nil else {
                return VolumeKeySuppressionEvaluation(
                    decision: .passThrough,
                    state: nextState
                )
            }
            return VolumeKeySuppressionEvaluation(
                decision: .consume,
                state: nextState
            )
        }

        if nextState.latchedActions[event.action] != nil {
            nextState.latchedActions[event.action] = uptime
            return VolumeKeySuppressionEvaluation(
                decision: .consume,
                state: nextState
            )
        }

        guard mode == .conditional,
              authority?.isValid(at: uptime) == true else {
            return VolumeKeySuppressionEvaluation(
                decision: .passThrough,
                state: nextState
            )
        }

        nextState.latchedActions[event.action] = uptime
        return VolumeKeySuppressionEvaluation(
            decision: .consume,
            state: nextState
        )
    }
}
