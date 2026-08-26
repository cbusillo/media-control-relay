import MediaControlCore
import Testing
import UPnPMediaTarget
@testable import Media_Control_Relay

@Suite("Media target discovery model", .serialized)
@MainActor
struct MediaTargetDiscoveryModelTests {
    @Test("Discovery publishes generic explicit choices")
    func publishesChoices() async {
        let discovery = MediaTargetDiscoveryModel {
            [
                UPnPMediaTargetDiscoveryCandidate(
                    identity: MediaTargetIdentity(stableIdentifier: "fixture-private-id"),
                    ordinal: 1
                ),
            ]
        }

        discovery.startScan()
        await discoveryWaitUntil {
            if case .results = discovery.state { return true }
            return false
        }

        guard case let .results(choices) = discovery.state else {
            Issue.record("Expected discovery results")
            return
        }
        #expect(choices.map(\.label) == ["Media Renderer 1"])
        #expect(choices[0].label.wholeMatch(of: /Media Renderer \d+/) != nil)
    }

    @Test("Discovery errors remain generic")
    func errorsRemainGeneric() async {
        let discovery = MediaTargetDiscoveryModel {
            throw UPnPMediaTargetError.discoveryUnavailable
        }

        discovery.startScan()
        await discoveryWaitUntil { discovery.state == .failed }

        #expect(discovery.state == .failed)
    }

    @Test("Cancelled scans discard late results")
    func cancellationDiscardsLateResults() async {
        let scan = DeferredDiscoveryScan()
        let discovery = MediaTargetDiscoveryModel {
            await scan.result()
        }

        discovery.startScan()
        await discoveryWaitUntilAsync { await scan.isWaiting }
        discovery.cancelScan()
        await scan.finish([
            UPnPMediaTargetDiscoveryCandidate(
                identity: MediaTargetIdentity(stableIdentifier: "fixture-private-id"),
                ordinal: 1
            ),
        ])
        await Task.yield()

        #expect(discovery.state == .idle)
    }
}

@MainActor
private func discoveryWaitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for discovery state")
}

private func discoveryWaitUntilAsync(
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<100 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for asynchronous discovery state")
}

private actor DeferredDiscoveryScan {
    private var continuation: CheckedContinuation<
        [UPnPMediaTargetDiscoveryCandidate],
        Never
    >?

    var isWaiting: Bool {
        continuation != nil
    }

    func result() async -> [UPnPMediaTargetDiscoveryCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ candidates: [UPnPMediaTargetDiscoveryCandidate]) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: candidates)
    }
}
