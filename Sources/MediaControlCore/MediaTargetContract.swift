import Foundation

public struct MediaTargetIdentity: Equatable, Hashable, Sendable {
    public let stableIdentifier: String

    public init(stableIdentifier: String) {
        self.stableIdentifier = stableIdentifier
    }
}

public struct MediaTargetVolumeState: Equatable, Sendable {
    public let absoluteVolume: Int
    public let isMuted: Bool
    public let minimumVolume: Int
    public let maximumVolume: Int

    public init(
        absoluteVolume: Int,
        isMuted: Bool,
        minimumVolume: Int,
        maximumVolume: Int
    ) {
        self.minimumVolume = min(minimumVolume, maximumVolume)
        self.maximumVolume = max(minimumVolume, maximumVolume)
        self.absoluteVolume = min(
            max(absoluteVolume, self.minimumVolume),
            self.maximumVolume
        )
        self.isMuted = isMuted
    }

    public var boundedRange: ClosedRange<Int> {
        minimumVolume...maximumVolume
    }

    public func clamped(_ value: Int) -> Int {
        min(max(value, minimumVolume), maximumVolume)
    }
}

public enum MediaTargetVolumeOperation: Equatable, Sendable {
    case setVolume(Int)
    case setMuted(Bool)
}

public enum MediaTargetVolumePlan: Equatable, Sendable {
    case noChange
    case apply(MediaTargetVolumeOperation)
}

public enum MediaTargetFailure: Error, Equatable, Sendable {
    case permissionDenied
    case discoveryUnavailable
    case offline
    case capabilityUnavailable
    case timeout
    case malformedResponse
    case protocolFault
    case readBackMismatch
    case cancelled
}

public protocol MediaVolumeTarget: Sendable {
    var identity: MediaTargetIdentity { get }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState
}

public struct MediaTargetVolumeReconciler: Equatable, Sendable {
    public let step: Int
    public let maximumCoalescedStepCount: Int

    public init(
        step: Int = 1,
        maximumCoalescedStepCount: Int = VolumeCommandQueuePolicy.default.maximumBatchSize
    ) {
        self.step = max(1, step)
        self.maximumCoalescedStepCount = max(1, maximumCoalescedStepCount)
    }

    public func plan(
        _ action: VolumeAction,
        currentState: MediaTargetVolumeState,
        refreshedState: MediaTargetVolumeState? = nil,
        coalescedStepCount: Int = 1
    ) -> MediaTargetVolumePlan {
        let state = refreshedState ?? currentState

        switch action {
        case .up:
            return volumePlan(
                from: state,
                direction: 1,
                stepCount: coalescedStepCount
            )
        case .down:
            return volumePlan(
                from: state,
                direction: -1,
                stepCount: coalescedStepCount
            )
        case .mute:
            return .apply(.setMuted(!state.isMuted))
        }
    }

    public func verify(
        _ operation: MediaTargetVolumeOperation,
        confirmedState: MediaTargetVolumeState
    ) throws(MediaTargetFailure) -> MediaTargetVolumeState {
        let matches: Bool
        switch operation {
        case let .setVolume(expectedVolume):
            matches = confirmedState.absoluteVolume == expectedVolume
        case let .setMuted(expectedMuted):
            matches = confirmedState.isMuted == expectedMuted
        }

        guard matches else {
            throw .readBackMismatch
        }
        return confirmedState
    }

    private func volumePlan(
        from state: MediaTargetVolumeState,
        direction: Int,
        stepCount: Int
    ) -> MediaTargetVolumePlan {
        let normalizedStepCount = min(
            max(1, stepCount),
            maximumCoalescedStepCount
        )
        let (magnitude, multiplicationOverflow) = step.multipliedReportingOverflow(
            by: normalizedStepCount
        )
        guard !multiplicationOverflow else {
            return railPlan(from: state, direction: direction)
        }

        let delta = direction > 0 ? magnitude : -magnitude
        let (candidate, additionOverflow) = state.absoluteVolume.addingReportingOverflow(delta)
        guard !additionOverflow else {
            return railPlan(from: state, direction: direction)
        }

        let targetVolume = state.clamped(candidate)
        guard targetVolume != state.absoluteVolume else {
            return .noChange
        }
        return .apply(.setVolume(targetVolume))
    }

    private func railPlan(
        from state: MediaTargetVolumeState,
        direction: Int
    ) -> MediaTargetVolumePlan {
        let targetVolume = direction > 0 ? state.maximumVolume : state.minimumVolume
        guard targetVolume != state.absoluteVolume else {
            return .noChange
        }
        return .apply(.setVolume(targetVolume))
    }
}
