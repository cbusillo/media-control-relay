import Foundation

public struct MediaTargetCommandExecutor: Sendable {
    public let target: any MediaVolumeTarget
    public let reconciler: MediaTargetVolumeReconciler

    public init(
        target: any MediaVolumeTarget,
        reconciler: MediaTargetVolumeReconciler = MediaTargetVolumeReconciler()
    ) {
        self.target = target
        self.reconciler = reconciler
    }

    public func execute(
        _ action: VolumeAction,
        coalescedStepCount: Int = 1
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        let currentState = try await target.readState()
        switch reconciler.plan(
            action,
            currentState: currentState,
            coalescedStepCount: coalescedStepCount
        ) {
        case .noChange:
            return currentState
        case let .apply(operation):
            return try await target.apply(operation)
        }
    }
}
