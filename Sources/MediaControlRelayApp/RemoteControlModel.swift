import Foundation
import MediaControlCore
import Observation

struct RemoteControlDiscoveryChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

enum RemoteControlRuntimeAvailability: String, Equatable, Sendable {
    case available
    case helperNotInstalled = "not-installed"
    case helperDamaged = "damaged"
    case helperUnsupportedArchitecture = "unsupported-architecture"
}

enum RemoteControlCredentialOperation: String, Equatable, Sendable {
    case read
    case write
    case remove
}

enum RemoteControlFailure: Error, Equatable, Sendable {
    case unavailable
    case offline
    case pairingFailed
    case unsupported
    case unsupportedAction
    case credential(RemoteControlCredentialOperation)
}

struct RemoteControlRuntimeResolution: Sendable {
    let availability: RemoteControlRuntimeAvailability
    let actuator: (any RemoteControlActuating)?
}

protocol RemoteControlRuntimeProviding: Sendable {
    func resolve() async -> RemoteControlRuntimeResolution
}

protocol RemoteControlActuating: Sendable {
    func hasStoredCredential() async throws -> Bool
    func resume() async throws -> MediaRemoteTargetState
    func discover() async throws -> [RemoteControlDiscoveryChoice]
    func beginPairing(targetID: String) async throws
    func finishPairing(pin: Int) async throws -> MediaRemoteTargetState
    func retryCredentialSave() async throws -> MediaRemoteTargetState
    func execute(_ action: MediaRemoteAction) async throws -> MediaRemoteTargetState
    func stop() async
    func clearStoredCredential() async throws
    func stopImmediately()
}

enum RemoteControlSetupState: Equatable, Sendable {
    case helperNotInstalled
    case helperDamaged
    case helperUnsupportedArchitecture
    case unconfigured
    case discovering
    case empty
    case choosing([RemoteControlDiscoveryChoice])
    case pairing(RemoteControlDiscoveryChoice, failedAttempts: Int)
    case connecting(reconnecting: Bool)
    case ready(Set<MediaRemoteCapability>)
    case unsupported
    case offline(manual: Bool)
    case credentialFailure(RemoteControlCredentialOperation)

    var targetState: MediaRemoteTargetState {
        switch self {
        case .helperNotInstalled, .helperDamaged, .unconfigured, .discovering, .empty, .choosing:
            return .unconfigured
        case .helperUnsupportedArchitecture:
            return .unsupported
        case .pairing:
            return .pairingRequired
        case .connecting:
            return .connecting
        case let .ready(capabilities):
            return .ready(capabilities: capabilities)
        case .unsupported:
            return .unsupported
        case .offline, .credentialFailure:
            return .offline
        }
    }

    var diagnosticName: String {
        switch self {
        case .helperNotInstalled: "helper-not-installed"
        case .helperDamaged: "helper-damaged"
        case .helperUnsupportedArchitecture: "helper-unsupported-architecture"
        case .unconfigured: "unconfigured"
        case .discovering: "discovering"
        case .empty: "empty"
        case .choosing: "choosing"
        case .pairing: "pairing-required"
        case let .connecting(reconnecting): reconnecting ? "reconnecting" : "connecting"
        case .ready: "ready"
        case .unsupported: "unsupported"
        case let .offline(manual): manual ? "disconnected" : "offline"
        case let .credentialFailure(operation): "credential-\(operation.rawValue)-failed"
        }
    }
}

@MainActor
@Observable
final class RemoteControlModel {
    static let diagnosticFieldNames: Set<String> = [
        "remote_helper",
        "remote_state",
        "remote_capabilities",
        "remote_actions_accepted",
        "remote_actions_rejected",
        "remote_actions_duplicate_suppressed",
        "remote_actions_coalesced",
        "remote_actions_unsupported",
        "remote_actions_unavailable",
        "remote_commands_dispatched",
        "remote_commands_failed",
        "remote_queue_dropped",
    ]

    private(set) var availability: RemoteControlRuntimeAvailability = .helperNotInstalled
    private(set) var state: RemoteControlSetupState = .helperNotInstalled
    var pairingPIN = ""
    private(set) var operationMessage: String?
    private(set) var actionsAccepted = 0
    private(set) var actionsRejected = 0
    private(set) var actionsDuplicateSuppressed = 0
    private(set) var actionsCoalesced = 0
    private(set) var actionsUnsupported = 0
    private(set) var actionsUnavailable = 0
    private(set) var commandsDispatched = 0
    private(set) var commandsFailed = 0
    private(set) var queueDropped = 0

    private let runtimeProvider: any RemoteControlRuntimeProviding
    private let clock: @Sendable () -> UInt64
    private var actuator: (any RemoteControlActuating)?
    private var availabilityTask: Task<Void, Never>?
    private var availabilityGeneration: UInt64 = 0
    private var operationTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    private var commandPumpTask: Task<Void, Never>?
    private var commandPumpGeneration: UInt64 = 0
    private var commandQueue = MediaRemoteCommandQueue()
    private var commandGeneration: UInt64 = 0
    private var lastAction: (action: MediaRemoteAction, timestamp: UInt64)?
    private var selectedChoice: RemoteControlDiscoveryChoice?

    init(
        runtimeProvider: any RemoteControlRuntimeProviding,
        clock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.runtimeProvider = runtimeProvider
        self.clock = clock
        refreshAvailability()
    }

    var capabilities: Set<MediaRemoteCapability> {
        state.targetState.capabilities
    }

    var diagnosticsFields: [String: String] {
        [
            "remote_helper": availability.rawValue,
            "remote_state": state.diagnosticName,
            "remote_capabilities": capabilities.map(\.rawValue).sorted().joined(separator: ","),
            "remote_actions_accepted": actionsAccepted.formatted(),
            "remote_actions_rejected": actionsRejected.formatted(),
            "remote_actions_duplicate_suppressed": actionsDuplicateSuppressed.formatted(),
            "remote_actions_coalesced": actionsCoalesced.formatted(),
            "remote_actions_unsupported": actionsUnsupported.formatted(),
            "remote_actions_unavailable": actionsUnavailable.formatted(),
            "remote_commands_dispatched": commandsDispatched.formatted(),
            "remote_commands_failed": commandsFailed.formatted(),
            "remote_queue_dropped": queueDropped.formatted(),
        ]
    }

    var terminationStopper: (@Sendable () -> Void)? {
        guard let actuator else { return nil }
        return { actuator.stopImmediately() }
    }

    func refreshAvailability() {
        cancelCurrentOperation()
        commandPumpTask?.cancel()
        commandPumpTask = nil
        commandPumpGeneration &+= 1
        invalidateCommands()
        availabilityGeneration &+= 1
        availabilityTask?.cancel()
        actuator = nil
        operationMessage = nil
        let generation = availabilityGeneration
        let runtimeProvider = runtimeProvider
        availabilityTask = Task { [weak self] in
            let resolution = await runtimeProvider.resolve()
            guard !Task.isCancelled,
                  let self,
                  self.availabilityGeneration == generation else {
                return
            }
            self.availabilityTask = nil
            self.applyRuntimeResolution(resolution)
        }
    }

    private func applyRuntimeResolution(_ resolution: RemoteControlRuntimeResolution) {
        availability = resolution.availability
        actuator = resolution.actuator
        operationMessage = nil
        switch resolution.availability {
        case .available:
            state = .unconfigured
            startIfNeeded()
        case .helperNotInstalled:
            state = .helperNotInstalled
        case .helperDamaged:
            state = .helperDamaged
        case .helperUnsupportedArchitecture:
            state = .helperUnsupportedArchitecture
        }
    }

    func startIfNeeded() {
        guard operationTask == nil, let actuator else { return }
        let generation = beginOperation()
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                guard try await actuator.hasStoredCredential() else {
                    guard self?.isCurrentOperation(generation) == true else { return }
                    self?.state = .unconfigured
                    return
                }
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .connecting(reconnecting: false)
                let remoteState = try await actuator.resume()
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(remoteState)
            } catch is CancellationError {
                return
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func discover() {
        guard let actuator else {
            actionsUnavailable += 1
            return
        }
        let generation = beginOperation()
        operationMessage = nil
        state = .discovering
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                let choices = try await actuator.discover()
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = choices.isEmpty ? .empty : .choosing(choices)
            } catch is CancellationError {
                return
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func cancelDiscovery() {
        cancelCurrentOperation()
        selectedChoice = nil
        pairingPIN = ""
        invalidateCommands()
        if let actuator {
            Task { await actuator.stop() }
        }
        state = .unconfigured
    }

    func select(_ choice: RemoteControlDiscoveryChoice) {
        guard let actuator else { return }
        let generation = beginOperation()
        selectedChoice = choice
        pairingPIN = ""
        operationMessage = nil
        state = .connecting(reconnecting: false)
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                try await actuator.beginPairing(targetID: choice.id)
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .pairing(choice, failedAttempts: 0)
            } catch is CancellationError {
                return
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func finishPairing() {
        guard let actuator,
              let choice = selectedChoice,
              pairingPIN.count == 4,
              let pin = Int(pairingPIN) else {
            return
        }
        let attempts: Int
        if case let .pairing(_, failedAttempts) = state {
            attempts = failedAttempts
        } else {
            attempts = 0
        }
        let generation = beginOperation()
        state = .connecting(reconnecting: false)
        operationMessage = nil
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                let remoteState = try await actuator.finishPairing(pin: pin)
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(remoteState)
                self?.pairingPIN = ""
            } catch is CancellationError {
                return
            } catch RemoteControlFailure.pairingFailed {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.pairingPIN = ""
                self?.operationMessage = "That PIN didn’t work. Try again."
                self?.state = .pairing(choice, failedAttempts: attempts + 1)
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func retryCredentialSave() {
        guard case .credentialFailure(.write) = state,
              let actuator else { return }
        let generation = beginOperation()
        operationMessage = nil
        state = .connecting(reconnecting: false)
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                let remoteState = try await actuator.retryCredentialSave()
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(remoteState)
            } catch is CancellationError {
                return
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func retry() {
        guard let actuator else { return }
        let generation = beginOperation()
        operationMessage = nil
        state = .connecting(reconnecting: true)
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                let remoteState = try await actuator.resume()
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(remoteState)
            } catch is CancellationError {
                return
            } catch let failure as RemoteControlFailure {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.apply(failure)
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.state = .offline(manual: false)
            }
        }
    }

    func disconnect() {
        cancelCurrentOperation()
        invalidateCommands()
        state = .offline(manual: true)
        if let actuator {
            Task { await actuator.stop() }
        }
    }

    func forgetCredentials() {
        guard let actuator else { return }
        let generation = beginOperation()
        operationMessage = nil
        let previousState = state
        operationTask = Task { [weak self] in
            defer { self?.finishOperation(generation) }
            do {
                try await actuator.clearStoredCredential()
                guard self?.isCurrentOperation(generation) == true else { return }
                await actuator.stop()
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.selectedChoice = nil
                self?.pairingPIN = ""
                self?.invalidateCommands()
                self?.resetCounters()
                self?.state = .unconfigured
            } catch is CancellationError {
                return
            } catch {
                guard self?.isCurrentOperation(generation) == true else { return }
                self?.operationMessage = "Couldn’t remove the saved connection. Try again."
                self?.state = previousState
            }
        }
    }

    func handle(_ action: MediaRemoteAction) {
        guard let actuator else {
            actionsUnavailable += 1
            return
        }
        let now = clock()
        if shouldSuppress(action, at: now) {
            actionsDuplicateSuppressed += 1
            return
        }
        do {
            try state.targetState.require(action)
        } catch MediaRemoteFailure.unsupportedAction(_) {
            actionsUnsupported += 1
            return
        } catch {
            actionsUnavailable += 1
            return
        }

        let before = commandQueue.pendingActions
        do {
            try commandQueue.enqueue(action)
        } catch {
            queueDropped += 1
            return
        }
        let after = commandQueue.pendingActions
        guard before != after else { return }
        if after.count <= before.count {
            actionsCoalesced += 1
        }
        actionsAccepted += 1
        lastAction = (action, now)
        startCommandPump(actuator: actuator)
    }

    func recordRejectedAction() {
        actionsRejected += 1
    }

    func shutdown() {
        cancelCurrentOperation()
        commandPumpTask?.cancel()
        commandPumpTask = nil
        commandPumpGeneration &+= 1
        invalidateCommands()
    }

    private func startCommandPump(actuator: any RemoteControlActuating) {
        guard commandPumpTask == nil else { return }
        commandPumpGeneration &+= 1
        let pumpGeneration = commandPumpGeneration
        commandPumpTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if commandPumpGeneration == pumpGeneration {
                    commandPumpTask = nil
                }
            }
            while !Task.isCancelled, let action = commandQueue.dequeue() {
                let generation = commandGeneration
                commandsDispatched += 1
                do {
                    let remoteState = try await actuator.execute(action)
                    guard generation == commandGeneration else { continue }
                    apply(remoteState)
                } catch let failure as RemoteControlFailure {
                    commandsFailed += 1
                    guard generation == commandGeneration else { continue }
                    apply(failure)
                } catch {
                    commandsFailed += 1
                    guard generation == commandGeneration else { continue }
                    state = .offline(manual: false)
                    invalidateCommands()
                }
            }
        }
    }

    private func apply(_ targetState: MediaRemoteTargetState) {
        switch targetState {
        case .unconfigured:
            state = .unconfigured
        case .pairingRequired:
            if let selectedChoice {
                state = .pairing(selectedChoice, failedAttempts: 0)
            } else {
                state = .unconfigured
            }
        case .connecting:
            state = .connecting(reconnecting: false)
        case let .ready(capabilities):
            state = .ready(capabilities)
        case .unsupported:
            state = .unsupported
            invalidateCommands()
        case .offline:
            state = .offline(manual: false)
            invalidateCommands()
        }
    }

    private func apply(_ failure: RemoteControlFailure) {
        switch failure {
        case .pairingFailed:
            if let selectedChoice {
                state = .pairing(selectedChoice, failedAttempts: 1)
            }
        case .unsupported:
            state = .unsupported
            invalidateCommands()
        case .credential(let operation):
            state = .credentialFailure(operation)
            invalidateCommands()
        case .unsupportedAction:
            actionsUnsupported += 1
        case .unavailable, .offline:
            state = .offline(manual: false)
            invalidateCommands()
        }
    }

    private func shouldSuppress(_ action: MediaRemoteAction, at timestamp: UInt64) -> Bool {
        let interval: UInt64
        switch action {
        case .seek, .volume:
            return false
        case .navigate:
            interval = 80_000_000
        case .select, .back, .home, .playPause, .previous, .next:
            interval = 300_000_000
        }
        guard let lastAction,
              lastAction.action == action,
              timestamp >= lastAction.timestamp else {
            return false
        }
        return timestamp - lastAction.timestamp < interval
    }

    private func invalidateCommands() {
        commandGeneration &+= 1
        _ = commandQueue.invalidate()
    }

    private func resetCounters() {
        actionsAccepted = 0
        actionsRejected = 0
        actionsDuplicateSuppressed = 0
        actionsCoalesced = 0
        actionsUnsupported = 0
        actionsUnavailable = 0
        commandsDispatched = 0
        commandsFailed = 0
        queueDropped = 0
    }

    private func beginOperation() -> UInt64 {
        operationGeneration &+= 1
        operationTask?.cancel()
        return operationGeneration
    }

    private func cancelCurrentOperation() {
        operationGeneration &+= 1
        operationTask?.cancel()
        operationTask = nil
    }

    private func isCurrentOperation(_ generation: UInt64) -> Bool {
        operationGeneration == generation
    }

    private func finishOperation(_ generation: UInt64) {
        if operationGeneration == generation {
            operationTask = nil
        }
    }
}
