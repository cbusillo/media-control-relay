import Testing
@testable import MediaControlCore

@Suite("Media target command executor")
struct MediaTargetCommandExecutorTests {
    @Test("Relative actions use one current-state read and one absolute write")
    func executesAbsoluteWrite() async throws {
        let target = ExecutorTargetStub(
            initialState: state(volume: 5, muted: false)
        )
        let executor = MediaTargetCommandExecutor(target: target)

        let confirmed = try await executor.execute(.up)

        #expect(confirmed.absoluteVolume == 6)
        #expect(await target.readCount == 1)
        #expect(await target.appliedOperations == [.setVolume(6)])
    }

    @Test("Rail actions return current state without a write")
    func railIsNoChange() async throws {
        let target = ExecutorTargetStub(
            initialState: state(volume: 10, muted: false, maximum: 10)
        )
        let executor = MediaTargetCommandExecutor(target: target)

        let confirmed = try await executor.execute(.up)

        #expect(confirmed.absoluteVolume == 10)
        #expect(await target.appliedOperations.isEmpty)
    }

    @Test("Target failures propagate through the neutral taxonomy")
    func propagatesFailure() async {
        let target = ExecutorTargetStub(
            initialState: state(volume: 5, muted: false),
            readFailure: .authenticationRejected
        )
        let executor = MediaTargetCommandExecutor(target: target)

        await #expect(throws: MediaTargetFailure.authenticationRejected) {
            _ = try await executor.execute(.mute)
        }
    }
}

private actor ExecutorTargetStub: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState: MediaTargetVolumeState
    private let readFailure: MediaTargetFailure?
    private(set) var readCount = 0
    private(set) var appliedOperations: [MediaTargetVolumeOperation] = []

    init(
        initialState: MediaTargetVolumeState,
        readFailure: MediaTargetFailure? = nil
    ) {
        currentState = initialState
        self.readFailure = readFailure
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if let readFailure { throw readFailure }
        return currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        appliedOperations.append(operation)
        switch operation {
        case let .setVolume(volume):
            currentState = state(
                volume: volume,
                muted: currentState.isMuted,
                maximum: currentState.maximumVolume
            )
        case let .setMuted(isMuted):
            currentState = state(
                volume: currentState.absoluteVolume,
                muted: isMuted,
                maximum: currentState.maximumVolume
            )
        }
        return currentState
    }
}

private func state(
    volume: Int,
    muted: Bool,
    maximum: Int = 10
) -> MediaTargetVolumeState {
    MediaTargetVolumeState(
        absoluteVolume: volume,
        isMuted: muted,
        minimumVolume: 0,
        maximumVolume: maximum
    )
}
