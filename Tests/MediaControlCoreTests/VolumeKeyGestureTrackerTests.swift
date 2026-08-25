import Testing
@testable import MediaControlCore

@Suite("Volume key gesture tracking")
struct VolumeKeyGestureTrackerTests {
    @Test("A press emits immediately and repeats on the policy cadence")
    func repeatCadence() {
        var tracker = VolumeKeyGestureTracker()
        #expect(tracker.ingest(event(.up, .pressed, at: 1)) == [.up])
        #expect(tracker.tick(at: 1.44) == [])
        #expect(tracker.tick(at: 1.45) == [.up])
        #expect(tracker.tick(at: 1.74) == [])
        #expect(tracker.tick(at: 1.75) == [.up])
    }

    @Test("OS repeat events do not duplicate the app cadence")
    func ignoresOSRepeat() {
        var tracker = VolumeKeyGestureTracker()
        #expect(tracker.ingest(event(.down, .pressed, at: 1)) == [.down])
        #expect(tracker.ingest(event(.down, .pressed, repeat: true, at: 1.1)) == [])
    }

    @Test("Mute emits once and never enters a hold")
    func muteDoesNotRepeat() {
        var tracker = VolumeKeyGestureTracker()
        #expect(tracker.ingest(event(.mute, .pressed, at: 1)) == [.mute])
        #expect(tracker.nextDeadline == nil)
        #expect(tracker.tick(at: 10) == [])
    }

    @Test("Duplicate initial presses are collapsed")
    func duplicatePress() {
        var tracker = VolumeKeyGestureTracker()
        #expect(tracker.ingest(event(.up, .pressed, at: 1)) == [.up])
        #expect(tracker.ingest(event(.up, .pressed, at: 1.1)) == [])
    }

    @Test("A release permits a second press inside the duplicate window")
    func rapidSecondPressAfterRelease() {
        var tracker = VolumeKeyGestureTracker()
        #expect(tracker.ingest(event(.up, .pressed, at: 1)) == [.up])
        #expect(tracker.ingest(event(.up, .released, at: 1.04)) == [])
        #expect(tracker.ingest(event(.up, .pressed, at: 1.1)) == [.up])
        #expect(tracker.ingest(event(.mute, .pressed, at: 2)) == [.mute])
        #expect(tracker.ingest(event(.mute, .released, at: 2.03)) == [])
        #expect(tracker.ingest(event(.mute, .pressed, at: 2.09)) == [.mute])
    }

    @Test("Release settles and ends the hold")
    func releaseSettles() {
        var tracker = VolumeKeyGestureTracker()
        _ = tracker.ingest(event(.up, .pressed, at: 1))
        #expect(tracker.ingest(event(.up, .released, at: 1.2)) == [])
        #expect(tracker.tick(at: 1.319) == [])
        #expect(tracker.tick(at: 1.32) == [])
        #expect(tracker.nextDeadline == nil)
    }

    @Test("A missed release is bounded by the maximum repeat ticks")
    func missedReleaseBound() {
        let policy = VolumeCommandQueuePolicy(maximumRepeatTicks: 2)
        var tracker = VolumeKeyGestureTracker(policy: policy)
        _ = tracker.ingest(event(.down, .pressed, at: 1))
        #expect(tracker.tick(at: 1.45) == [.down])
        #expect(tracker.tick(at: 1.75) == [.down])
        #expect(tracker.nextDeadline == nil)
        #expect(tracker.tick(at: 20) == [])
    }

    @Test("Queue backpressure drops a due tick while preserving the bound")
    func queueBackpressure() {
        let policy = VolumeCommandQueuePolicy(maximumRepeatTicks: 1)
        var tracker = VolumeKeyGestureTracker(policy: policy)
        #expect(tracker.ingest(event(.up, .pressed, at: 1), pendingCount: 18) == [])
        #expect(tracker.tick(at: 1.45, pendingCount: 18) == [])
        #expect(tracker.nextDeadline == nil)
    }

    private func event(
        _ action: VolumeAction,
        _ phase: VolumeKeyPhase,
        repeat isRepeat: Bool = false,
        at timestamp: Double
    ) -> VolumeKeyEvent {
        VolumeKeyEvent(
            action: action,
            phase: phase,
            isRepeat: isRepeat,
            timestamp: timestamp
        )
    }
}
