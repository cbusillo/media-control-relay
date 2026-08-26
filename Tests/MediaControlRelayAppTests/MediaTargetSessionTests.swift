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

        #expect(await session.probe() == .reachable)
    }

    @Test("Transport and target permission failures remain unreachable")
    func failedProbe() async {
        for failure in [
            MediaTargetFailure.offline,
            .timeout,
            .permissionDenied,
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

            #expect(await session.probe() == .unreachable)
        }
    }

    @Test("Cancelled probes return unknown")
    func cancelledProbe() async {
        let target = SessionTargetStub(result: .failure(.cancelled))
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )

        #expect(await session.probe() == .unknown)
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

private actor InvalidationRecorder {
    private(set) var reasons: [MediaTargetSessionInvalidation] = []

    func record(_ reason: MediaTargetSessionInvalidation) {
        reasons.append(reason)
    }
}

private func makeState() -> MediaTargetVolumeState {
    MediaTargetVolumeState(
        absoluteVolume: 5,
        isMuted: false,
        minimumVolume: 0,
        maximumVolume: 10
    )
}
