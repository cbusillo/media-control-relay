import Testing
@testable import VolumeBridgeCore

@Suite("Volume command policy")
struct VolumeCommandQueuePolicyTests {
    private let policy = VolumeCommandQueuePolicy.default

    @Test("Queue bounds reject overflow")
    func queueBounds() {
        #expect(policy.canEnqueue(pendingCount: 17))
        #expect(!policy.canEnqueue(pendingCount: 18))
        #expect(!policy.canEnqueue(pendingCount: 17, adding: 2))
        #expect(!policy.canEnqueue(pendingCount: -1))
    }

    @Test("Repeat cadence accelerates and remains bounded")
    func repeatCadence() {
        #expect(policy.repeatDelay(afterCompletedTicks: 0) == 0.45)
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 1), 0.30))
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 3), 0.30))
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 4), 0.24))
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 9), 0.24))
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 10), 0.20))
        #expect(isApproximately(policy.repeatDelay(afterCompletedTicks: 23), 0.20))
        #expect(policy.repeatDelay(afterCompletedTicks: 24) == nil)
    }

    @Test("Batch size respects request, queue, and transport bounds")
    func batchBounds() {
        #expect(policy.boundedBatchSize(requestedCount: 8, pendingCount: 0) == 6)
        #expect(policy.boundedBatchSize(requestedCount: 4, pendingCount: 16) == 2)
        #expect(policy.boundedBatchSize(requestedCount: 4, pendingCount: 18) == 0)
        #expect(policy.boundedBatchSize(requestedCount: 0, pendingCount: 0) == 0)
    }

    @Test("Duplicate and release timing windows are deterministic")
    func timingWindows() {
        #expect(policy.isDuplicateEvent(previousTimestamp: 1, currentTimestamp: 1.15))
        #expect(!policy.isDuplicateEvent(previousTimestamp: 1, currentTimestamp: 1.151))
        #expect(!policy.isDuplicateEvent(previousTimestamp: 2, currentTimestamp: 1))
        #expect(!policy.isReleaseSettled(releaseTimestamp: 1, currentTimestamp: 1.119))
        #expect(policy.isReleaseSettled(releaseTimestamp: 1, currentTimestamp: 1.12))
    }

    @Test("Mute never repeats")
    func muteDoesNotRepeat() {
        #expect(policy.shouldRepeat(.up))
        #expect(policy.shouldRepeat(.down))
        #expect(!policy.shouldRepeat(.mute))
    }

    @Test("Prototype-safe timing defaults remain pinned")
    func timingDefaults() {
        #expect(policy.initialRepeatDelay == 0.45)
        #expect(policy.releaseDebounce == 0.12)
        #expect(policy.duplicateEventWindow == 0.15)
        #expect(policy.maximumRepeatTicks == 24)
        #expect(policy.maximumBatchSize == 6)
        #expect(policy.maximumPendingCommands == 18)
    }

    @Test("Custom repeat timing never becomes slower after the first repeat")
    func customRepeatTiming() {
        let fastPolicy = VolumeCommandQueuePolicy(initialRepeatDelay: 0.05)
        #expect(fastPolicy.repeatDelay(afterCompletedTicks: 0) == 0.05)
        #expect(fastPolicy.repeatDelay(afterCompletedTicks: 1) == 0.05)
        #expect(fastPolicy.repeatDelay(afterCompletedTicks: 10) == 0.05)
    }

    private func isApproximately(
        _ value: Double?,
        _ expected: Double
    ) -> Bool {
        guard let value else {
            return false
        }
        return abs(value - expected) < 0.000_001
    }
}
