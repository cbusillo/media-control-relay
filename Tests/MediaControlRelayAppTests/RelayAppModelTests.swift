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

    @Test("Eligible actions execute through the physical target")
    func eligibleActionExecutes() async {
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
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.appliedOperations == [.setVolume(6)] }

        #expect(harness.model.targetCommandsDispatched == 1)
        #expect(harness.model.targetCommandsFailed == 0)
        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Route mismatch suppresses physical command execution")
    func routeMismatchSuppressesCommand() async {
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
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        harness.model.handleVolumeAction(.mute)
        await Task.yield()

        #expect(await target.appliedOperations.isEmpty)
        #expect(harness.model.commandsSuppressed == 1)
        #expect(harness.model.relayState == .dormant)
        harness.cleanup()
    }

    @Test("Physical commands remain serialized and bounded")
    func commandsAreSerializedAndBounded() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let maximumPending = VolumeCommandQueuePolicy.default.maximumPendingCommands
        for _ in 0..<(maximumPending + 2) {
            harness.model.handleVolumeAction(.mute)
        }
        await waitUntilAsync { await target.applyCount == 1 }

        #expect(harness.model.commandsRecorded == maximumPending)
        #expect(harness.model.commandsSuppressed == 2)
        #expect(await target.maximumConcurrentApplyCount == 1)

        for expectedCount in 1...maximumPending {
            await target.releaseCurrentApply()
            if expectedCount < maximumPending {
                await waitUntilAsync {
                    await target.applyCount == expectedCount + 1
                }
            }
        }
        await waitUntil { harness.model.targetCommandsDispatched == maximumPending }

        #expect(await target.maximumConcurrentApplyCount == 1)
        harness.cleanup()
    }

    @Test("Sleep suppresses stale command completion")
    func sleepSuppressesStaleCompletion() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 1 }
        harness.routeObserver.sleep()
        await target.releaseCurrentApply()
        await Task.yield()

        #expect(harness.model.relayState == .dormant)
        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Command failures publish only coarse private diagnostics")
    func commandFailureDiagnosticsRemainPrivate() async {
        let sensitiveIdentifier = "secret-udn-1234"
        let target = FailingCommandTarget(stableIdentifier: sensitiveIdentifier)
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: sensitiveIdentifier),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntil { harness.model.relayState == .offline }

        let diagnostics = harness.model.diagnosticsSummary
        #expect(harness.model.targetCommandsFailed == 1)
        #expect(diagnostics.contains("target_connection=local-network"))
        #expect(!diagnostics.contains(sensitiveIdentifier))
        #expect(!diagnostics.contains("timeout"))
        #expect(!diagnostics.contains("protocolFault"))
        harness.cleanup()
    }

    @Test("Preview commands preserve synchronous recording behavior")
    func previewCommandsRemainSynchronous() async {
        let harness = makeHarness(
            configuration: makePreviewConfiguration(),
            session: nil
        )

        await waitUntil { harness.model.relayState == .active }
        for _ in 0..<20 {
            harness.model.handleVolumeAction(.mute)
        }

        #expect(harness.model.commandsRecorded == 20)
        #expect(harness.model.commandsSuppressed == 0)
        #expect(harness.model.targetCommandsDispatched == 0)
        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Physical command execution preserves FIFO action order")
    func commandOrderIsFIFO() async {
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
        harness.model.handleVolumeAction(.up)
        harness.model.handleVolumeAction(.mute)
        harness.model.handleVolumeAction(.down)
        await waitUntilAsync { await target.appliedOperations.count == 3 }

        #expect(
            await target.appliedOperations == [
                .setVolume(6),
                .setMuted(true),
                .setVolume(5),
            ]
        )
        harness.cleanup()
    }

    @Test("Event tap failure cancels in-flight physical commands")
    func eventTapFailureCancelsCommand() async {
        let target = BlockingCommandTarget()
        let monitor = FlakyVolumeKeyMonitor()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            volumeKeyMonitor: monitor
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 1 }
        monitor.shouldFail = true
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .needsPermission }
        await target.releaseCurrentApply()
        await Task.yield()

        #expect(harness.model.relayState == .needsPermission)
        #expect(harness.model.targetCommandsFailed == 0)

        monitor.shouldFail = false
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 2 }
        await target.releaseCurrentApply()
        await waitUntil { harness.model.targetCommandsDispatched == 2 }

        #expect(harness.model.relayState == .active)
        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Preview target recovers after event tap failure")
    func previewRecoversAfterEventTapFailure() async {
        let monitor = FlakyVolumeKeyMonitor()
        let harness = makeHarness(
            configuration: makePreviewConfiguration(),
            session: nil,
            volumeKeyMonitor: monitor
        )

        await waitUntil { harness.model.relayState == .active }
        monitor.shouldFail = true
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .needsPermission }

        monitor.shouldFail = false
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)

        #expect(harness.model.commandsRecorded == 1)
        #expect(harness.model.commandsSuppressed == 0)
        #expect(harness.model.targetCommandsDispatched == 0)
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
    session: MediaTargetSession?,
    volumeKeyMonitor: any VolumeKeyMonitoring = InactiveVolumeKeyMonitor()
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
        volumeKeyMonitor: volumeKeyMonitor,
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
private final class FlakyVolumeKeyMonitor: VolumeKeyMonitoring {
    let events = AsyncStream<VolumeKeyEvent> { continuation in
        continuation.finish()
    }
    var shouldFail = false

    func start() throws {
        if shouldFail {
            throw VolumeKeyMonitorError.eventTapUnavailable
        }
    }

    func stop() {}
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

    private var currentState = makeVolumeState()
    private(set) var readCount = 0
    private(set) var appliedOperations: [MediaTargetVolumeOperation] = []

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        return currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        appliedOperations.append(operation)
        currentState = applying(operation, to: currentState)
        return currentState
    }
}

private actor BlockingCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeVolumeState()
    private var continuation: CheckedContinuation<Void, Never>?
    private var concurrentApplyCount = 0
    private(set) var applyCount = 0
    private(set) var maximumConcurrentApplyCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyCount += 1
        concurrentApplyCount += 1
        maximumConcurrentApplyCount = max(
            maximumConcurrentApplyCount,
            concurrentApplyCount
        )
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        concurrentApplyCount -= 1
        currentState = applying(operation, to: currentState)
        return currentState
    }

    func releaseCurrentApply() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private actor FailingCommandTarget: MediaVolumeTarget {
    nonisolated let identity: MediaTargetIdentity

    init(stableIdentifier: String) {
        identity = MediaTargetIdentity(stableIdentifier: stableIdentifier)
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .timeout
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

private func makePreviewConfiguration() -> RelayConfiguration {
    RelayConfiguration(
        target: RelayTargetMetadata(
            kind: .preview,
            name: "Preview Target"
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

private func applying(
    _ operation: MediaTargetVolumeOperation,
    to state: MediaTargetVolumeState
) -> MediaTargetVolumeState {
    switch operation {
    case let .setVolume(volume):
        return MediaTargetVolumeState(
            absoluteVolume: volume,
            isMuted: state.isMuted,
            minimumVolume: state.minimumVolume,
            maximumVolume: state.maximumVolume
        )
    case let .setMuted(isMuted):
        return MediaTargetVolumeState(
            absoluteVolume: state.absoluteVolume,
            isMuted: isMuted,
            minimumVolume: state.minimumVolume,
            maximumVolume: state.maximumVolume
        )
    }
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
