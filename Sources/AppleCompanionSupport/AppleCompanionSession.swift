import Foundation
import MediaControlCore

public enum AppleCompanionSessionState: Equatable, Sendable {
    case dormant
    case pairingRequired
    case connecting
    case ready(Set<MediaRemoteCapability>)
    case reconnecting
    case offline
    case unsupported
}

public actor AppleCompanionSession {
    public private(set) var state: AppleCompanionSessionState = .dormant
    public private(set) var generation: UInt64 = 0

    private struct PendingRequest {
        let generation: UInt64
        let appliesSuccessfulState: Bool
        let continuation: CheckedContinuation<AppleCompanionReply, Error>
    }

    private struct PendingCredentialReply {
        let generation: UInt64
        let reply: AppleCompanionReply
    }

    private let transportFactory: @Sendable () async throws -> any AppleCompanionTransport
    private let helperProcess: AppleCompanionHelperProcess?
    private let keychain: any AppleCompanionKeychain
    private let keychainAccount: String
    private let timeoutNanoseconds: UInt64
    private let reconnectBaseDelayNanoseconds: UInt64
    private let maximumReconnectAttempts: Int
    private var transport: (any AppleCompanionTransport)?
    private var startTask: Task<Void, Error>?
    private var readerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pending: [UInt64: PendingRequest] = [:]
    private var timeoutTasks: [UInt64: Task<Void, Never>] = [:]
    private var nextRequestID: UInt64 = 0
    private var reconnectAttempt = 0
    private var pendingCredentialReply: PendingCredentialReply?

    public init(
        keychain: any AppleCompanionKeychain,
        keychainAccount: String = "primary",
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        reconnectBaseDelayNanoseconds: UInt64 = 100_000_000,
        maximumReconnectAttempts: Int = 6,
        helperProcess: AppleCompanionHelperProcess? = nil,
        transportFactory: @escaping @Sendable () async throws -> any AppleCompanionTransport
    ) {
        self.keychain = keychain
        self.keychainAccount = keychainAccount
        self.timeoutNanoseconds = timeoutNanoseconds
        self.reconnectBaseDelayNanoseconds = max(1, reconnectBaseDelayNanoseconds)
        self.maximumReconnectAttempts = max(0, maximumReconnectAttempts)
        self.helperProcess = helperProcess
        self.transportFactory = transportFactory
    }

    deinit {
        readerTask?.cancel()
        reconnectTask?.cancel()
        transport?.close()
        helperProcess?.stop()
    }

    public func start() async throws {
        guard transport == nil else { return }
        if let startTask {
            try await startTask.value
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        state = .connecting
        let expectedGeneration = generation
        let helperProcess = helperProcess
        let transportFactory = transportFactory
        let task = Task { [self] in
            do {
                try await helperProcess?.start()
                let newTransport = try await transportFactory()
                try await newTransport.start()
                try installStartedTransport(
                    newTransport,
                    expectedGeneration: expectedGeneration
                )
            } catch {
                failStart(expectedGeneration: expectedGeneration)
                throw AppleCompanionProtocolError.unavailable
            }
        }
        startTask = task
        try await task.value
    }

    public func resume() async throws -> AppleCompanionReply {
        do {
            if let secret = try storedSecret() {
                let reply = try await send(.connect(secret))
                if reply.secret != nil {
                    try persistSecret(from: reply)
                }
                return reply
            }
        } catch AppleCompanionKeychainError.invalidData {
            try clearStoredSecret()
        }
        return try await send(.status)
    }

    public func discover() async throws -> [AppleCompanionTarget] {
        try await send(.discover).targets
    }

    public func beginPairing(targetID: String) async throws {
        pendingCredentialReply = nil
        _ = try await send(.beginPairing(targetID: targetID))
    }

    @discardableResult
    public func finishPairing(pin: Int) async throws -> AppleCompanionReply {
        let pairingGeneration = generation
        let reply = try await send(
            .finishPairing(pin: pin),
            appliesSuccessfulState: false
        )
        do {
            try persistSecret(from: reply)
        } catch let error as AppleCompanionKeychainError {
            if error != .invalidData {
                pendingCredentialReply = PendingCredentialReply(
                    generation: pairingGeneration,
                    reply: reply
                )
            }
            throw error
        }
        pendingCredentialReply = nil
        guard pairingGeneration == generation else {
            throw AppleCompanionProtocolError.generationInvalidated
        }
        apply(reply.state, capabilities: reply.capabilities)
        return reply
    }

    public func retryPersistingPairingCredential() throws -> AppleCompanionReply {
        guard let pendingCredentialReply else {
            throw AppleCompanionKeychainError.invalidData
        }
        let reply = pendingCredentialReply.reply
        try persistSecret(from: reply)
        self.pendingCredentialReply = nil
        guard pendingCredentialReply.generation == generation else {
            throw AppleCompanionProtocolError.generationInvalidated
        }
        apply(reply.state, capabilities: reply.capabilities)
        return reply
    }

    public func execute(_ action: MediaRemoteAction) async throws -> AppleCompanionReply {
        guard case let .ready(capabilities) = state else {
            throw AppleCompanionProtocolError.unavailable
        }
        guard capabilities.contains(action.requiredCapability) else {
            throw AppleCompanionProtocolError.remote(.unsupportedAction)
        }
        return try await send(.action(AppleCompanionAction(action)))
    }

    public func stop() {
        startTask?.cancel()
        startTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        readerTask?.cancel()
        readerTask = nil
        transport?.close()
        transport = nil
        helperProcess?.stop()
        invalidatePending(with: AppleCompanionProtocolError.connectionLost)
        reconnectAttempt = 0
        pendingCredentialReply = nil
        generation &+= 1
        state = .dormant
    }

    public func invalidate() {
        generation &+= 1
        pendingCredentialReply = nil
        startTask?.cancel()
        startTask = nil
        invalidatePending(with: AppleCompanionProtocolError.generationInvalidated)
        transport?.close()
        transport = nil
        helperProcess?.stop()
        readerTask?.cancel()
        readerTask = nil
        state = .reconnecting
        scheduleReconnect()
    }

    public func storedSecret() throws -> AppleCompanionConnectionSecret? {
        guard let data = try keychain.read(account: keychainAccount) else { return nil }
        do {
            return try JSONDecoder().decode(AppleCompanionConnectionSecret.self, from: data)
        } catch {
            throw AppleCompanionKeychainError.invalidData
        }
    }

    public func clearStoredSecret() throws {
        try keychain.delete(account: keychainAccount)
        pendingCredentialReply = nil
    }

    private func send(
        _ operation: AppleCompanionOperation,
        appliesSuccessfulState: Bool = true
    ) async throws -> AppleCompanionReply {
        try Task.checkCancellation()
        if transport == nil {
            try await start()
        }
        try Task.checkCancellation()
        guard let transport else { throw AppleCompanionProtocolError.unavailable }

        nextRequestID &+= 1
        let requestID = nextRequestID
        let requestGeneration = generation
        let frame = try AppleCompanionFrameCodec().encode(
            .request(
                AppleCompanionRequest(
                    id: requestID,
                    generation: requestGeneration,
                    operation: operation
                )
            )
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = PendingRequest(
                    generation: requestGeneration,
                    appliesSuccessfulState: appliesSuccessfulState,
                    continuation: continuation
                )
                if Task.isCancelled {
                    fail(requestID: requestID, error: CancellationError())
                    return
                }
                Task {
                    do {
                        try await transport.send(frame)
                    } catch {
                        self.fail(
                            requestID: requestID,
                            error: AppleCompanionProtocolError.connectionLost
                        )
                    }
                }
                timeoutTasks[requestID] = Task {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    self.timeout(requestID: requestID, generation: requestGeneration)
                }
            }
        } onCancel: {
            Task { await self.fail(requestID: requestID, error: CancellationError()) }
        }
    }

    private func persistSecret(from reply: AppleCompanionReply) throws {
        guard let secret = reply.secret else { throw AppleCompanionKeychainError.invalidData }
        do {
            try keychain.write(try JSONEncoder().encode(secret), account: keychainAccount)
        } catch let error as AppleCompanionKeychainError {
            throw error
        } catch {
            throw AppleCompanionKeychainError.unavailable
        }
    }

    private func startReader(for transport: any AppleCompanionTransport) {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            var codec = AppleCompanionFrameCodec()
            do {
                for try await data in transport.incoming {
                    for message in try codec.append(data) {
                        await self?.receive(message)
                    }
                }
                try codec.finish()
                await self?.disconnected()
            } catch {
                await self?.disconnected()
            }
        }
    }

    private func receive(_ message: AppleCompanionWireMessage) {
        guard case let .reply(reply) = message,
              reply.generation == generation,
              let request = pending[reply.id],
              request.generation == generation else {
            return
        }
        pending.removeValue(forKey: reply.id)
        timeoutTasks.removeValue(forKey: reply.id)?.cancel()
        if let error = reply.error {
            if error != .unsupportedAction {
                apply(reply.state, capabilities: reply.capabilities)
            }
            request.continuation.resume(throwing: AppleCompanionProtocolError.remote(error))
            return
        }
        if request.appliesSuccessfulState {
            apply(reply.state, capabilities: reply.capabilities)
        }
        reconnectAttempt = 0
        request.continuation.resume(returning: reply)
    }

    private func apply(_ remoteState: AppleCompanionState, capabilities: Set<MediaRemoteCapability>) {
        switch remoteState {
        case .dormant: state = .dormant
        case .pairingRequired: state = .pairingRequired
        case .connecting: state = .connecting
        case .ready: state = .ready(capabilities)
        case .offline: state = .offline
        case .unsupported: state = .unsupported
        }
    }

    private func disconnected() {
        guard let disconnectedTransport = transport else { return }
        transport = nil
        disconnectedTransport.close()
        readerTask = nil
        generation &+= 1
        invalidatePending(with: AppleCompanionProtocolError.connectionLost)
        state = .reconnecting
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard reconnectAttempt < maximumReconnectAttempts else {
            state = .offline
            return
        }
        let delay: UInt64 = min(
            5_000_000_000,
            reconnectBaseDelayNanoseconds << UInt64(min(reconnectAttempt, 5))
        )
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.reconnect()
        }
    }

    private func reconnect() async {
        reconnectTask = nil
        do {
            try await start()
            _ = try await resume()
        } catch {
            state = .reconnecting
            scheduleReconnect()
        }
    }

    private func fail(requestID: UInt64, error: Error) {
        guard let request = pending.removeValue(forKey: requestID) else { return }
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        request.continuation.resume(throwing: error)
    }

    private func timeout(requestID: UInt64, generation: UInt64) {
        guard let request = pending[requestID], request.generation == generation else { return }
        pending.removeValue(forKey: requestID)
        timeoutTasks.removeValue(forKey: requestID)
        request.continuation.resume(throwing: AppleCompanionProtocolError.timeout)
    }

    private func invalidatePending(with error: Error) {
        let requests = pending.values
        pending.removeAll(keepingCapacity: true)
        let tasks = timeoutTasks.values
        timeoutTasks.removeAll(keepingCapacity: true)
        for task in tasks {
            task.cancel()
        }
        for request in requests {
            request.continuation.resume(throwing: error)
        }
    }

    private func installStartedTransport(
        _ newTransport: any AppleCompanionTransport,
        expectedGeneration: UInt64
    ) throws(AppleCompanionProtocolError) {
        guard generation == expectedGeneration, transport == nil else {
            newTransport.close()
            throw .generationInvalidated
        }
        startTask = nil
        transport = newTransport
        state = .dormant
        startReader(for: newTransport)
    }

    private func failStart(expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        startTask = nil
        state = .offline
        scheduleReconnect()
    }
}
