import Foundation
import MediaControlCore
import Testing
@testable import Media_Control_Relay

@Suite("Remote control model", .serialized)
@MainActor
struct RemoteControlModelTests {
    @Test("Helper availability is explicit and does not invent a runtime")
    func helperAvailability() {
        let missing = RemoteControlModel(
            runtimeProvider: FakeRemoteRuntimeProvider(
                resolution: RemoteControlRuntimeResolution(
                    availability: .helperNotInstalled,
                    actuator: nil
                )
            )
        )
        let damaged = RemoteControlModel(
            runtimeProvider: FakeRemoteRuntimeProvider(
                resolution: RemoteControlRuntimeResolution(
                    availability: .helperDamaged,
                    actuator: nil
                )
            )
        )

        #expect(missing.state == .helperNotInstalled)
        #expect(damaged.state == .helperDamaged)
        #expect(missing.terminationStopper == nil)
    }

    @Test("Stored credentials resume into the helper-reported ready state")
    func resumeStoredCredential() async {
        let actuator = FakeRemoteActuator(
            storedCredential: true,
            resumeState: .ready(capabilities: [.navigation, .select])
        )
        let model = makeModel(actuator: actuator)

        await eventually { model.state == .ready([.navigation, .select]) }
        #expect(await actuator.resumeCount == 1)
        #expect(model.capabilities == [.navigation, .select])
    }

    @Test("Discovery and two-stage pairing retain only ephemeral display choices")
    func discoveryAndPairing() async {
        let choice = RemoteControlDiscoveryChoice(id: "private-id", name: "Living Room")
        let actuator = FakeRemoteActuator(
            discoveries: [choice],
            pairingState: .ready(capabilities: [.navigation, .playPause])
        )
        let model = makeModel(actuator: actuator)
        await eventually { model.state == .unconfigured }

        model.discover()
        await eventually { model.state == .choosing([choice]) }
        model.select(choice)
        await eventually { model.state == .pairing(choice, failedAttempts: 0) }
        model.pairingPIN = "1234"
        model.finishPairing()
        await eventually { model.state == .ready([.navigation, .playPause]) }

        #expect(await actuator.beginPairingIDs == ["private-id"])
        #expect(await actuator.finishedPINs == [1234])
        #expect(!model.diagnosticsFields.values.joined().contains("private-id"))
        #expect(!model.diagnosticsFields.values.joined().contains("Living Room"))
        #expect(!model.diagnosticsFields.values.joined().contains("1234"))
    }

    @Test("Discrete duplicates are suppressed while volume deltas coalesce")
    func suppressionAndCoalescing() async {
        let clock = LockedClock(value: 1_000_000_000)
        let actuator = FakeRemoteActuator(
            storedCredential: true,
            resumeState: .ready(capabilities: [.select, .relativeVolume]),
            executeState: .ready(capabilities: [.select, .relativeVolume])
        )
        let model = makeModel(actuator: actuator, clock: clock.now)
        await eventually { model.state == .ready([.select, .relativeVolume]) }

        model.handle(.select)
        model.handle(.select)
        model.handle(.volume(1))
        model.handle(.volume(1))

        await eventually { await actuator.executedActions.count >= 2 }
        #expect(model.actionsAccepted == 3)
        #expect(model.actionsDuplicateSuppressed == 1)
        #expect(model.actionsCoalesced == 1)
        #expect(await actuator.executedActions.contains(.volume(2)))
    }

    @Test("Pairing save failure remains explicit and recoverable")
    func pairingSaveFailure() async {
        let choice = RemoteControlDiscoveryChoice(id: "private-id", name: "Living Room")
        let actuator = FakeRemoteActuator(
            discoveries: [choice],
            pairingFailure: .credential(.write)
        )
        let model = makeModel(actuator: actuator)
        await eventually { model.state == .unconfigured }

        model.discover()
        await eventually { model.state == .choosing([choice]) }
        model.select(choice)
        await eventually { model.state == .pairing(choice, failedAttempts: 0) }
        model.pairingPIN = "1234"
        model.finishPairing()
        await eventually { model.state == .credentialFailure(.write) }
        model.retryCredentialSave()
        await eventually { model.state == .ready([.navigation]) }

        #expect(await actuator.finishedPINs == [1234])
        #expect(await actuator.retryCredentialSaveCount == 1)
    }

    @Test("Pairing save retry cannot be started twice")
    func pairingSaveRetryIsSingleFlight() async {
        let choice = RemoteControlDiscoveryChoice(id: "private-id", name: "Living Room")
        let actuator = FakeRemoteActuator(
            discoveries: [choice],
            pairingFailure: .credential(.write),
            retryCredentialSaveDelayNanoseconds: 50_000_000
        )
        let model = makeModel(actuator: actuator)
        await eventually { model.state == .unconfigured }

        model.discover()
        await eventually { model.state == .choosing([choice]) }
        model.select(choice)
        await eventually { model.state == .pairing(choice, failedAttempts: 0) }
        model.pairingPIN = "1234"
        model.finishPairing()
        await eventually { model.state == .credentialFailure(.write) }

        model.retryCredentialSave()
        #expect(model.state == .connecting(reconnecting: false))
        model.retryCredentialSave()
        await eventually { model.state == .ready([.navigation]) }

        #expect(await actuator.retryCredentialSaveCount == 1)
    }

    @Test("Credential removal failure preserves the truthful ready state")
    func removalFailure() async {
        let actuator = FakeRemoteActuator(
            storedCredential: true,
            resumeState: .ready(capabilities: [.home]),
            clearFailure: .credential(.remove)
        )
        let model = makeModel(actuator: actuator)
        await eventually { model.state == .ready([.home]) }

        model.forgetCredentials()
        await eventually { model.operationMessage != nil }

        #expect(model.state == .ready([.home]))
        #expect(model.operationMessage == "Couldn’t remove the saved connection. Try again.")
        #expect(await actuator.stopCount == 0)
    }

    @Test("Cancelling discovery keeps the explicit unconfigured state")
    func cancelDiscovery() async {
        let actuator = DelayedDiscoveryActuator()
        let model = RemoteControlModel(
            runtimeProvider: FakeRemoteRuntimeProvider(
                resolution: RemoteControlRuntimeResolution(
                    availability: .available,
                    actuator: actuator
                )
            )
        )
        await eventually { model.state == .unconfigured }

        model.discover()
        #expect(model.state == .discovering)
        model.cancelDiscovery()
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(model.state == .unconfigured)
    }

    @Test("Remote child diagnostics override zero-valued app placeholders")
    func remoteDiagnosticsReachAppSummary() async {
        let actuator = FakeRemoteActuator()
        let remote = makeModel(actuator: actuator)
        await eventually { remote.state == .unconfigured }
        remote.recordRejectedAction()
        remote.handle(.select)
        let app = makeRelayAppModel(remoteControl: remote)

        #expect(app.diagnosticsSummary.contains("remote_actions_rejected=1"))
        #expect(app.diagnosticsSummary.contains("remote_actions_unavailable=1"))
    }

    @Test("Delegate keeps cold-launch volume and remote queues independent")
    func independentDelegateQueues() {
        let delegate = RelayAppDelegate()
        let volumeURL = URL(string: "media-control-relay://control/volume/up")!
        let remoteURL = URL(string: "media-control-relay://remote/select")!

        delegate.receive(urls: Array(repeating: volumeURL, count: 20))
        delegate.receive(urls: Array(repeating: remoteURL, count: 20))

        #expect(delegate.pendingActionCount == 16)
        #expect(delegate.pendingRemoteActionCount == 16)
    }

    @Test("Cold-launch remote overflow stays in remote diagnostics")
    func remoteOverflowAttribution() {
        let delegate = RelayAppDelegate()
        let remoteURL = URL(string: "media-control-relay://remote/select")!
        delegate.receive(urls: Array(repeating: remoteURL, count: 17))
        let app = makeRelayAppModel(remoteControl: nil)

        delegate.attach(model: app)

        #expect(app.diagnosticsSummary.contains("external_actions_rejected=0"))
        #expect(app.diagnosticsSummary.contains("remote_actions_rejected=1"))
        #expect(app.diagnosticsSummary.contains("remote_actions_unavailable=16"))
    }

    private func makeModel(
        actuator: FakeRemoteActuator,
        clock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) -> RemoteControlModel {
        RemoteControlModel(
            runtimeProvider: FakeRemoteRuntimeProvider(
                resolution: RemoteControlRuntimeResolution(
                    availability: .available,
                    actuator: actuator
                )
            ),
            clock: clock
        )
    }

    private func makeRelayAppModel(remoteControl: RemoteControlModel?) -> RelayAppModel {
        let suiteName = "RemoteControlModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RelayAppModel(
            routeObserver: InactiveRouteObserver(),
            networkPathObserver: InactiveNetworkPathObserver(),
            configurationStore: RelayConfigurationStore(defaults: defaults),
            volumeKeyMonitor: InactiveVolumeKeyMonitor(),
            inputMonitoringAccess: .denied,
            accessibilityAccess: .denied,
            launchAtLoginClient: LaunchAtLoginClient(
                status: { .notRegistered },
                register: {},
                unregister: {},
                openSystemSettingsLoginItems: {}
            ),
            remoteControl: remoteControl
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Condition did not become true")
    }
}

private struct FakeRemoteRuntimeProvider: RemoteControlRuntimeProviding {
    let resolution: RemoteControlRuntimeResolution

    func resolve() -> RemoteControlRuntimeResolution {
        resolution
    }
}

private actor FakeRemoteActuator: RemoteControlActuating {
    private let storedCredential: Bool
    private let resumeState: MediaRemoteTargetState
    private let discoveries: [RemoteControlDiscoveryChoice]
    private let pairingState: MediaRemoteTargetState
    private let pairingFailure: RemoteControlFailure?
    private let retryCredentialSaveState: MediaRemoteTargetState
    private let retryCredentialSaveDelayNanoseconds: UInt64
    private let executeState: MediaRemoteTargetState
    private let clearFailure: RemoteControlFailure?

    private(set) var resumeCount = 0
    private(set) var beginPairingIDs: [String] = []
    private(set) var finishedPINs: [Int] = []
    private(set) var retryCredentialSaveCount = 0
    private(set) var executedActions: [MediaRemoteAction] = []
    private(set) var stopCount = 0

    init(
        storedCredential: Bool = false,
        resumeState: MediaRemoteTargetState = .unconfigured,
        discoveries: [RemoteControlDiscoveryChoice] = [],
        pairingState: MediaRemoteTargetState = .ready(capabilities: []),
        pairingFailure: RemoteControlFailure? = nil,
        retryCredentialSaveState: MediaRemoteTargetState = .ready(capabilities: [.navigation]),
        retryCredentialSaveDelayNanoseconds: UInt64 = 0,
        executeState: MediaRemoteTargetState = .ready(capabilities: []),
        clearFailure: RemoteControlFailure? = nil
    ) {
        self.storedCredential = storedCredential
        self.resumeState = resumeState
        self.discoveries = discoveries
        self.pairingState = pairingState
        self.pairingFailure = pairingFailure
        self.retryCredentialSaveState = retryCredentialSaveState
        self.retryCredentialSaveDelayNanoseconds = retryCredentialSaveDelayNanoseconds
        self.executeState = executeState
        self.clearFailure = clearFailure
    }

    func hasStoredCredential() -> Bool {
        storedCredential
    }

    func resume() -> MediaRemoteTargetState {
        resumeCount += 1
        return resumeState
    }

    func discover() -> [RemoteControlDiscoveryChoice] {
        discoveries
    }

    func beginPairing(targetID: String) {
        beginPairingIDs.append(targetID)
    }

    func finishPairing(pin: Int) throws -> MediaRemoteTargetState {
        finishedPINs.append(pin)
        if let pairingFailure { throw pairingFailure }
        return pairingState
    }

    func retryCredentialSave() async throws -> MediaRemoteTargetState {
        retryCredentialSaveCount += 1
        if retryCredentialSaveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: retryCredentialSaveDelayNanoseconds)
        }
        return retryCredentialSaveState
    }

    func execute(_ action: MediaRemoteAction) -> MediaRemoteTargetState {
        executedActions.append(action)
        return executeState
    }

    func stop() {
        stopCount += 1
    }

    func clearStoredCredential() throws {
        if let clearFailure { throw clearFailure }
    }

    nonisolated func stopImmediately() {}
}

private actor DelayedDiscoveryActuator: RemoteControlActuating {
    func hasStoredCredential() -> Bool { false }
    func resume() -> MediaRemoteTargetState { .unconfigured }

    func discover() async throws -> [RemoteControlDiscoveryChoice] {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return []
    }

    func beginPairing(targetID: String) {}
    func finishPairing(pin: Int) -> MediaRemoteTargetState { .unsupported }
    func retryCredentialSave() -> MediaRemoteTargetState { .unsupported }
    func execute(_ action: MediaRemoteAction) -> MediaRemoteTargetState { .unsupported }
    func stop() {}
    func clearStoredCredential() {}
    nonisolated func stopImmediately() {}
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(value: UInt64) {
        self.value = value
    }

    func now() -> UInt64 {
        lock.withLock { value }
    }
}
