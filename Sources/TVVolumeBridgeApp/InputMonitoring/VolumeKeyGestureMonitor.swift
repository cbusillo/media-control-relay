import Foundation
import VolumeBridgeCore

@MainActor
final class VolumeKeyGestureMonitor {
    let actions: AsyncStream<VolumeAction>

    private let continuation: AsyncStream<VolumeAction>.Continuation
    private var tracker: VolumeKeyGestureTracker
    private var deadlineTask: Task<Void, Never>?

    init(policy: VolumeCommandQueuePolicy = .default) {
        let stream = AsyncStream<VolumeAction>.makeStream()
        actions = stream.stream
        continuation = stream.continuation
        tracker = VolumeKeyGestureTracker(policy: policy)
    }

    deinit {
        deadlineTask?.cancel()
        continuation.finish()
    }

    func ingest(_ event: VolumeKeyEvent) {
        emit(tracker.ingest(event))
        scheduleNextDeadline()
    }

    func cancel() {
        deadlineTask?.cancel()
        deadlineTask = nil
        tracker.cancelHold()
    }

    private func tick() {
        emit(tracker.tick(at: ProcessInfo.processInfo.systemUptime))
        scheduleNextDeadline()
    }

    private func emit(_ actions: [VolumeAction]) {
        for action in actions {
            continuation.yield(action)
        }
    }

    private func scheduleNextDeadline() {
        deadlineTask?.cancel()
        guard let deadline = tracker.nextDeadline else {
            deadlineTask = nil
            return
        }

        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        deadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.tick()
        }
    }
}
