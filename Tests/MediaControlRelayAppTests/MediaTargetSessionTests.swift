import MediaControlCore
import Testing
import UPnPMediaTarget
@testable import Media_Control_Relay

@Suite("Media target session", .serialized)
struct MediaTargetSessionTests {
    @Test("Successful probes report reachable")
    func successfulProbe() async {
        let target = SessionTargetStub(result: .success(makeState()))
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.probe()
        #expect(outcome?.reachability == .reachable)
        #expect(outcome?.confirmedState == makeState())
        #expect(outcome?.generation == 1)
    }

    @Test("Probe and command outcomes carry newer generations")
    func outcomesCarryMonotonicGenerations() async {
        let target = SessionCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let probe = await session.probe()
        let command = await session.execute(.up)

        #expect(probe?.generation == 1)
        #expect(command?.generation == 2)
        #expect(command?.confirmedState?.absoluteVolume == 6)
    }

    @Test("Generic transport and target failures remain unreachable")
    func failedProbe() async {
        for failure in [
            MediaTargetFailure.offline,
            .timeout,
            .capabilityUnavailable,
            .discoveryUnavailable,
            .malformedResponse,
            .protocolFault,
        ] {
            let target = SessionTargetStub(result: .failure(failure))
            let session = MediaTargetSession(
                target: target,
                invalidateResolution: { _ in }
            )

            let outcome = await session.probe()
            #expect(outcome?.reachability == .unreachable)
            #expect(outcome?.confirmedState == nil)
        }
    }

    @Test("Target authentication rejection remains distinct")
    func authenticationRejectedProbe() async {
        let target = SessionTargetStub(result: .failure(.authenticationRejected))
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.probe()
        #expect(outcome?.reachability == .authenticationRejected)
        #expect(outcome?.confirmedState == nil)
    }

    @Test("Local-network denial remains distinct")
    func localNetworkDeniedProbe() async {
        let target = SessionTargetStub(result: .failure(.localNetworkDenied))
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.probe()
        #expect(outcome?.reachability == .localNetworkDenied)
        #expect(outcome?.confirmedState == nil)
    }

    @Test("Cancelled probes publish nothing")
    func cancelledProbe() async {
        let target = SessionTargetStub(result: .failure(.cancelled))
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.probe()
        #expect(outcome == nil)
    }

    @Test("Invalidation discards a stale in-flight probe")
    func invalidationDiscardsProbe() async {
        let target = BlockingSessionTarget()
        let recorder = InvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { signal in
                await recorder.record(signal)
            }
        )

        let probe = Task { await session.probe() }
        await target.waitUntilReadStarted()
        await session.invalidate(.routeContextChanged)
        await target.releaseRead()

        #expect(await probe.value == nil)
        #expect(await recorder.reasons == [.routeContextChanged])
    }

    @Test("Older invalidation requests cannot supersede newer network context")
    func staleInvalidationRequestIsIgnored() async {
        let target = SessionTargetStub(result: .success(makeState()))
        let recorder = InvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { signal in
                await recorder.record(signal)
            }
        )

        await session.invalidate(.networkContextChanged, requestID: 2)
        await session.invalidate(.routeContextChanged, requestID: 1)

        #expect(await recorder.reasons == [.networkContextChanged])
    }

    @Test("Factory rejects blank stable identities")
    func factoryRejectsBlankIdentity() {
        let configuration = RelayConfiguration(
            target: RelayTargetMetadata(
                kind: .upnpMediaRenderer,
                name: "UPnP Media Target",
                stableIdentifier: "  \n  "
            ),
            activationRule: ActivationRule(
                audioOutputMatch: "Fixture Output",
                requiresDisplay: false
            )
        )

        #expect(MediaTargetSessionFactory.make(configuration: configuration) == nil)
    }

    @Test("Successful commands report reachable after confirmed apply")
    func successfulCommand() async {
        let target = SessionCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.execute(.up)
        #expect(outcome?.reachability == .reachable)
        #expect(outcome?.confirmedState == makeState(absoluteVolume: 6))
        #expect(await target.appliedOperations == [.setVolume(6)])
    }

    @Test("Command failures stay coarse and cancellation publishes nothing")
    func failedCommand() async {
        for failure in [
            MediaTargetFailure.offline,
            .timeout,
            .capabilityUnavailable,
            .discoveryUnavailable,
            .malformedResponse,
            .protocolFault,
            .readBackMismatch,
        ] {
            let target = SessionCommandFailureTarget(failure: failure)
            let session = MediaTargetSession(
                target: target,
                invalidateResolution: { _ in }
            )

            let outcome = await session.execute(.mute)
            #expect(outcome?.reachability == .unreachable)
            #expect(outcome?.confirmedState == nil)
        }

        let cancelledTarget = SessionCommandFailureTarget(failure: .cancelled)
        let cancelledSession = MediaTargetSession(
            target: cancelledTarget,
            invalidateResolution: { _ in }
        )
        let cancelledOutcome = await cancelledSession.execute(.mute)
        #expect(cancelledOutcome == nil)
    }

    @Test("Command authentication rejection remains distinct")
    func authenticationRejectedCommand() async {
        let target = SessionCommandFailureTarget(failure: .authenticationRejected)
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.execute(.mute)
        #expect(outcome?.reachability == .authenticationRejected)
        #expect(outcome?.confirmedState == nil)
    }

    @Test("Command local-network denial remains distinct")
    func localNetworkDeniedCommand() async {
        let target = SessionCommandFailureTarget(failure: .localNetworkDenied)
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let outcome = await session.execute(.mute)
        #expect(outcome?.reachability == .localNetworkDenied)
        #expect(outcome?.confirmedState == nil)
    }

    @Test("Invalidation discards stale command success")
    func invalidationDiscardsCommand() async {
        let target = BlockingSessionCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let command = Task { await session.execute(.mute) }
        await target.waitUntilApplyStarted()
        await session.invalidate(.lifecycleChanged)
        await target.releaseApply()

        #expect(await command.value == nil)
    }

    @Test("Cancelled command tasks never touch the target")
    func cancelledCommandDoesNotExecute() async {
        let target = SessionCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        let command = Task {
            await Task.yield()
            return await session.execute(.mute)
        }
        command.cancel()

        #expect(await command.value == nil)
        #expect(await target.appliedOperations.isEmpty)
    }
}

private actor SessionTargetStub: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private let result: Result<MediaTargetVolumeState, MediaTargetFailure>

    init(result: Result<MediaTargetVolumeState, MediaTargetFailure>) {
        self.result = result
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        switch result {
        case let .success(state):
            return state
        case let .failure(failure):
            throw failure
        }
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor BlockingSessionTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var readStarted = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilReadStarted() async {
        while !readStarted {
            await Task.yield()
        }
    }

    func releaseRead() {
        released = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readStarted = true
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }
        return makeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor SessionCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeState()
    private(set) var appliedOperations: [MediaTargetVolumeOperation] = []

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        appliedOperations.append(operation)
        switch operation {
        case let .setVolume(volume):
            currentState = MediaTargetVolumeState(
                absoluteVolume: volume,
                isMuted: currentState.isMuted,
                minimumVolume: currentState.minimumVolume,
                maximumVolume: currentState.maximumVolume
            )
        case let .setMuted(isMuted):
            currentState = MediaTargetVolumeState(
                absoluteVolume: currentState.absoluteVolume,
                isMuted: isMuted,
                minimumVolume: currentState.minimumVolume,
                maximumVolume: currentState.maximumVolume
            )
        }
        return currentState
    }
}

private actor SessionCommandFailureTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private let failure: MediaTargetFailure

    init(failure: MediaTargetFailure) {
        self.failure = failure
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        makeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw failure
    }
}

private actor BlockingSessionCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var applyStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilApplyStarted() async {
        while !applyStarted {
            await Task.yield()
        }
    }

    func releaseApply() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        makeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return makeState()
    }
}

private actor InvalidationRecorder {
    private(set) var reasons: [MediaTargetSessionInvalidation] = []

    func record(_ reason: MediaTargetSessionInvalidation) {
        reasons.append(reason)
    }
}

private func makeState(absoluteVolume: Int = 5) -> MediaTargetVolumeState {
    MediaTargetVolumeState(
        absoluteVolume: absoluteVolume,
        isMuted: false,
        minimumVolume: 0,
        maximumVolume: 10
    )
}
