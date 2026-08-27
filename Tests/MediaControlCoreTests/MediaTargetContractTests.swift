import Testing
@testable import MediaControlCore

@Suite("Media target contract")
struct MediaTargetContractTests {
    @Test("Volume state normalizes bounds and clamps values")
    func volumeStateClampsValues() {
        let state = MediaTargetVolumeState(
            absoluteVolume: 14,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 0
        )

        #expect(state.minimumVolume == 0)
        #expect(state.maximumVolume == 10)
        #expect(state.absoluteVolume == 10)
        #expect(state.boundedRange == 0...10)
        #expect(state.volumeStep == 1)
    }

    @Test("Volume state bounds its step to the normalized span")
    func volumeStateBoundsStep() {
        let state = MediaTargetVolumeState(
            absoluteVolume: 5,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10,
            volumeStep: 50
        )

        #expect(state.volumeStep == 10)
    }

    @Test("Relative actions map to one absolute operation")
    func relativeActionsMapToAbsoluteOperations() {
        let state = MediaTargetVolumeState(
            absoluteVolume: 6,
            isMuted: true,
            minimumVolume: 0,
            maximumVolume: 10,
            volumeStep: 2
        )

        let reconciler = MediaTargetVolumeReconciler()
        #expect(reconciler.plan(.up, currentState: state) == .apply(.setVolume(8)))
        #expect(reconciler.plan(.down, currentState: state) == .apply(.setVolume(4)))
        #expect(reconciler.plan(.mute, currentState: state) == .apply(.setMuted(false)))
    }

    @Test("Volume changes do not imply mute changes")
    func volumeChangesDoNotUnmute() {
        let reconciler = MediaTargetVolumeReconciler()
        let muted = MediaTargetVolumeState(
            absoluteVolume: 5,
            isMuted: true,
            minimumVolume: 0,
            maximumVolume: 10
        )

        #expect(reconciler.plan(.up, currentState: muted) == .apply(.setVolume(6)))
    }

    @Test("Rails produce explicit no-change plans")
    func railNoChange() {
        let reconciler = MediaTargetVolumeReconciler()
        let maximum = MediaTargetVolumeState(
            absoluteVolume: 10,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10
        )
        let minimum = MediaTargetVolumeState(
            absoluteVolume: 0,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10
        )

        #expect(reconciler.plan(.up, currentState: maximum) == .noChange)
        #expect(reconciler.plan(.down, currentState: minimum) == .noChange)
    }

    @Test("Held repeats coalesce into one bounded operation")
    func heldRepeatsCoalesce() {
        let state = MediaTargetVolumeState(
            absoluteVolume: 3,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 100,
            volumeStep: 2
        )

        let reconciler = MediaTargetVolumeReconciler()
        #expect(
            reconciler.plan(
                .up,
                currentState: state,
                coalescedStepCount: 3
            ) == .apply(.setVolume(8))
        )
        #expect(
            reconciler.plan(
                .up,
                currentState: state,
                coalescedStepCount: .max
            ) == .apply(.setVolume(14))
        )
    }

    @Test("Off-grid state advances to the next valid grid value")
    func offGridStateUsesGrid() {
        let reconciler = MediaTargetVolumeReconciler()
        let state = MediaTargetVolumeState(
            absoluteVolume: 7,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10,
            volumeStep: 4
        )

        #expect(reconciler.plan(.up, currentState: state) == .apply(.setVolume(8)))
        #expect(reconciler.plan(.down, currentState: state) == .apply(.setVolume(4)))
    }

    @Test("Non-grid maximum remains a valid rail")
    func nonGridMaximumIsRail() {
        let reconciler = MediaTargetVolumeReconciler()
        let state = MediaTargetVolumeState(
            absoluteVolume: 10,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10,
            volumeStep: 4
        )

        #expect(reconciler.plan(.up, currentState: state) == .noChange)
        #expect(reconciler.plan(.down, currentState: state) == .apply(.setVolume(8)))
    }

    @Test("Overflow falls back to a safe rail")
    func overflowFallsBackToRail() {
        let reconciler = MediaTargetVolumeReconciler()
        let state = MediaTargetVolumeState(
            absoluteVolume: Int.max - 1,
            isMuted: false,
            minimumVolume: Int.min,
            maximumVolume: Int.max,
            volumeStep: Int.max
        )

        #expect(reconciler.plan(.up, currentState: state) == .apply(.setVolume(Int.max)))
        #expect(reconciler.plan(.down, currentState: state) == .apply(.setVolume(Int.min)))
    }

    @Test("One supplied reread replaces stale cached state")
    func refreshedStateWins() {
        let reconciler = MediaTargetVolumeReconciler()
        let cached = MediaTargetVolumeState(
            absoluteVolume: 3,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10
        )
        let refreshed = MediaTargetVolumeState(
            absoluteVolume: 7,
            isMuted: true,
            minimumVolume: 0,
            maximumVolume: 10
        )

        #expect(
            reconciler.plan(
                .up,
                currentState: cached,
                refreshedState: refreshed,
                coalescedStepCount: 1
            ) == .apply(.setVolume(8))
        )
        #expect(reconciler.plan(.up, currentState: cached) == .apply(.setVolume(4)))
    }

    @Test("Read-back verifies only the requested dimension")
    func readBackAllowsUnrelatedOutOfBandChanges() throws {
        let reconciler = MediaTargetVolumeReconciler()
        let volumeConfirmation = MediaTargetVolumeState(
            absoluteVolume: 6,
            isMuted: true,
            minimumVolume: 0,
            maximumVolume: 10
        )
        let muteConfirmation = MediaTargetVolumeState(
            absoluteVolume: 9,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10
        )

        #expect(
            try reconciler.verify(
                .setVolume(6),
                confirmedState: volumeConfirmation
            ) == volumeConfirmation
        )
        #expect(
            try reconciler.verify(
                .setMuted(false),
                confirmedState: muteConfirmation
            ) == muteConfirmation
        )
    }

    @Test("Read-back mismatch uses the neutral failure taxonomy")
    func readBackMismatch() {
        let reconciler = MediaTargetVolumeReconciler()
        let confirmation = MediaTargetVolumeState(
            absoluteVolume: 7,
            isMuted: false,
            minimumVolume: 0,
            maximumVolume: 10
        )

        #expect(throws: MediaTargetFailure.readBackMismatch) {
            try reconciler.verify(
                .setVolume(6),
                confirmedState: confirmation
            )
        }
    }

    @Test("Async target apply returns confirmed state")
    func targetApplyReturnsConfirmedState() async throws {
        let target = StubMediaVolumeTarget()

        let confirmed = try await target.apply(.setVolume(7))

        #expect(confirmed.absoluteVolume == 7)
        #expect(try await target.readState() == confirmed)
        #expect(target.identity == MediaTargetIdentity(stableIdentifier: "test-target"))
    }
}

private actor StubMediaVolumeTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "test-target")

    private var state = MediaTargetVolumeState(
        absoluteVolume: 5,
        isMuted: false,
        minimumVolume: 0,
        maximumVolume: 10
    )

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        state
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        switch operation {
        case let .setVolume(volume):
            state = MediaTargetVolumeState(
                absoluteVolume: volume,
                isMuted: state.isMuted,
                minimumVolume: state.minimumVolume,
                maximumVolume: state.maximumVolume,
                volumeStep: state.volumeStep
            )
        case let .setMuted(isMuted):
            state = MediaTargetVolumeState(
                absoluteVolume: state.absoluteVolume,
                isMuted: isMuted,
                minimumVolume: state.minimumVolume,
                maximumVolume: state.maximumVolume,
                volumeStep: state.volumeStep
            )
        }
        return state
    }
}
