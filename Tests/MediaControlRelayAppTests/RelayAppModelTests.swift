import AppKit
import Foundation
import MediaControlCore
import Testing
@testable import Media_Control_Relay

@Suite("Relay app target health", .serialized)
@MainActor
struct RelayAppModelTests {
    @Test("Matching UPnP configuration becomes active after a successful probe")
    func successfulProbeBecomesActive() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }

        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Repeated permission refresh does not restart an in-flight probe")
    func permissionRefreshDoesNotRestartProbe() async {
        let target = BlockingAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntilAsync { await target.readCount == 1 }
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        harness.model.refreshInputMonitoring()
        await Task.yield()

        #expect(await target.readCount == 1)
        await target.releaseRead()
        await waitUntil { harness.model.relayState == .active }

        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Route mismatch suppresses a stale probe result")
    func routeMismatchSuppressesStaleProbe() async {
        let target = BlockingAppModelTarget()
        let recorder = AppModelInvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                await recorder.record(reason)
            }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntilAsync { await target.readCount == 1 }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        await target.releaseRead()
        await waitUntilAsync {
            await recorder.reasons.contains(.routeContextChanged)
        }

        #expect(harness.model.relayState == .dormant)
        harness.cleanup()
    }

    @Test("Missing stable identity resolves to offline instead of checking forever")
    func missingStableIdentityIsOffline() {
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: nil),
            session: nil
        )

        #expect(harness.model.relayState == .offline)
        harness.cleanup()
    }

    @Test("Offline target retries when permission state is refreshed")
    func offlineTargetRetriesOnRefresh() async {
        let target = RetryingAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .offline }
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }

        #expect(await target.readCount == 2)
        harness.cleanup()
    }

    @Test("Activation-equivalent route snapshots do not restart probing")
    func equivalentRouteDoesNotRestartProbe() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let initialReadCount = await target.readCount
        harness.routeObserver.publish(
            RouteSnapshot(
                audioOutput: AudioOutputSnapshot(
                    name: "Fixture Output",
                    transportKind: .display
                ),
                displays: [DisplaySnapshot(name: "Unrelated Display")]
            )
        )
        await Task.yield()

        #expect(await target.readCount == initialReadCount)
        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Wake performs one lifecycle-invalidated probe")
    func wakePerformsOneProbe() async {
        let target = AppModelTargetStub()
        let recorder = AppModelInvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                await recorder.record(reason)
            }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let initialReadCount = await target.readCount
        harness.routeObserver.sleep()
        await waitUntilAsync {
            await recorder.reasons.last == .lifecycleChanged
        }
        let wakeReasonStart = await recorder.reasons.count
        harness.routeObserver.wake(makeRoute())
        await waitUntilAsync { await target.readCount == initialReadCount + 1 }
        await waitUntil { harness.model.relayState == .active }

        let wakeReasons = await Array(recorder.reasons.dropFirst(wakeReasonStart))
        #expect(wakeReasons == [.lifecycleChanged])
        #expect(await target.readCount == initialReadCount + 1)
        harness.cleanup()
    }
}

@MainActor
private struct AppModelHarness {
    let model: RelayAppModel
    let routeObserver: AppModelRouteObserver
    let applicationNotificationCenter: NotificationCenter
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private func makeHarness(
    configuration: RelayConfiguration,
    session: MediaTargetSession?
) -> AppModelHarness {
    let suiteName = "com.shinycomputers.media-control-relay.app-model-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let configurationStore = RelayConfigurationStore(defaults: defaults)
    configurationStore.save(configuration)
    let routeObserver = AppModelRouteObserver(initialSnapshot: makeRoute())
    let applicationNotificationCenter = NotificationCenter()
    let model = RelayAppModel(
        routeObserver: routeObserver,
        configurationStore: configurationStore,
        volumeKeyMonitor: InactiveVolumeKeyMonitor(),
        inputMonitoringAccess: InputMonitoringAccessClient(
            preflight: { true },
            request: {}
        ),
        applicationNotificationCenter: applicationNotificationCenter,
        mediaTargetSessionFactory: { _ in session }
    )
    return AppModelHarness(
        model: model,
        routeObserver: routeObserver,
        applicationNotificationCenter: applicationNotificationCenter,
        defaults: defaults,
        suiteName: suiteName
    )
}

@MainActor
private final class AppModelRouteObserver: RouteObserving {
    var onSnapshot: ((RouteSnapshot) -> Void)?
    var onStateChange: ((RouteObservationState) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private(set) var state: RouteObservationState = .stopped
    private let initialSnapshot: RouteSnapshot

    init(initialSnapshot: RouteSnapshot) {
        self.initialSnapshot = initialSnapshot
    }

    func start() {
        state = .observing
        onStateChange?(state)
        onSnapshot?(initialSnapshot)
    }

    func stop() {
        state = .stopped
        onStateChange?(state)
    }

    func publish(_ snapshot: RouteSnapshot) {
        onSnapshot?(snapshot)
    }

    func sleep() {
        state = .suspended
        onStateChange?(state)
        onSleep?()
    }

    func wake(_ snapshot: RouteSnapshot) {
        state = .observing
        onStateChange?(state)
        onSnapshot?(snapshot)
        onWake?()
    }
}

private actor AppModelTargetStub: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        return makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor RetryingAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if readCount == 1 {
            throw .offline
        }
        return makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor BlockingAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }
        return makeVolumeState()
    }

    func releaseRead() {
        released = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor AppModelInvalidationRecorder {
    private(set) var reasons: [MediaTargetSessionInvalidation] = []

    func record(_ reason: MediaTargetSessionInvalidation) {
        reasons.append(reason)
    }
}

private func makeConfiguration(stableIdentifier: String?) -> RelayConfiguration {
    RelayConfiguration(
        target: RelayTargetMetadata(
            kind: .upnpMediaRenderer,
            name: "UPnP Media Target",
            stableIdentifier: stableIdentifier
        ),
        activationRule: ActivationRule(
            audioOutputMatch: "Fixture Output",
            requiresDisplay: false
        )
    )
}

private func makeRoute(name: String = "Fixture Output") -> RouteSnapshot {
    RouteSnapshot(
        audioOutput: AudioOutputSnapshot(
            name: name,
            transportKind: .display
        ),
        displays: []
    )
}

private func makeVolumeState() -> MediaTargetVolumeState {
    MediaTargetVolumeState(
        absoluteVolume: 5,
        isMuted: false,
        minimumVolume: 0,
        maximumVolume: 10
    )
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<100 {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for app-model state")
}

private func waitUntilAsync(
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<100 {
        if await condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for asynchronous app-model state")
}
