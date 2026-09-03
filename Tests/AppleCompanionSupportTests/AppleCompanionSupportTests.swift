import Foundation
import MediaControlCore
import Security
import Testing
@testable import AppleCompanionSupport

@Suite("Apple Companion support", .serialized)
struct AppleCompanionSupportTests {
    @Test("Legacy Keychain values migrate to the login Keychain")
    func legacyKeychainMigration() throws {
        let legacyData = Data("legacy-credential".utf8)
        let security = FakeKeychainSecurity(legacyData: legacyData)
        let keychain = SystemAppleCompanionKeychain(
            service: "fixture-service",
            security: security
        )

        #expect(try keychain.read(account: "fixture-account") == legacyData)
        #expect(security.currentData == legacyData)
        #expect(security.legacyData == nil)
        #expect(security.readBuckets == [.current, .legacy])
    }

    @Test("Legacy Keychain values remain usable when copy-forward fails")
    func legacyKeychainMigrationWriteFailure() throws {
        let legacyData = Data("legacy-credential".utf8)
        let security = FakeKeychainSecurity(
            legacyData: legacyData,
            addStatus: errSecInteractionNotAllowed
        )
        let keychain = SystemAppleCompanionKeychain(
            service: "fixture-service",
            security: security
        )

        #expect(try keychain.read(account: "fixture-account") == legacyData)
        #expect(security.currentData == nil)
        #expect(security.legacyData == legacyData)
    }

    @Test("An inaccessible legacy Keychain does not block fresh setup")
    func inaccessibleLegacyKeychain() throws {
        let security = FakeKeychainSecurity(legacyReadStatus: errSecInteractionNotAllowed)
        let keychain = SystemAppleCompanionKeychain(
            service: "fixture-service",
            security: security
        )

        #expect(try keychain.read(account: "fixture-account") == nil)
        #expect(security.readBuckets == [.current, .legacy])
    }

    @Test("Credential removal reports an undeletable legacy value")
    func legacyKeychainDeleteFailure() {
        let security = FakeKeychainSecurity(
            legacyData: Data("legacy-credential".utf8),
            legacyDeleteStatus: errSecInteractionNotAllowed
        )
        let keychain = SystemAppleCompanionKeychain(
            service: "fixture-service",
            security: security
        )

        #expect(throws: AppleCompanionKeychainError.accessDenied) {
            try keychain.delete(account: "fixture-account")
        }
        #expect(security.legacyData != nil)
    }

    @Test("Frame codec handles split messages and rejects malformed input")
    func frameCodec() throws {
        let request = AppleCompanionWireMessage.request(
            AppleCompanionRequest(id: 3, generation: 9, operation: .status)
        )
        let frame = try AppleCompanionFrameCodec().encode(request)
        var decoder = AppleCompanionFrameCodec()

        #expect(try decoder.append(frame.prefix(4)).isEmpty)
        #expect(try decoder.append(frame.dropFirst(4)) == [request])

        var malformed = AppleCompanionFrameCodec()
        #expect(throws: AppleCompanionProtocolError.malformedFrame) {
            _ = try malformed.append(Data("not-json\n".utf8))
        }
    }

    @Test("Frame codec rejects bounded-frame overflow")
    func frameLimit() {
        var codec = AppleCompanionFrameCodec()
        #expect(throws: AppleCompanionProtocolError.oversizedFrame) {
            _ = try codec.append(
                Data(repeating: 0x78, count: AppleCompanionFrameCodec.maximumFrameBytes + 1)
            )
        }
    }

    @Test("Swift wire codec matches the shared helper fixture")
    func sharedWireFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/wire-contract.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL))
        guard let object = fixture as? [String: Any],
              let requestObject = object["request"],
              let replyObject = object["reply"] else {
            Issue.record("Shared wire fixture is malformed")
            return
        }

        let requestData = try JSONSerialization.data(withJSONObject: requestObject)
        let replyData = try JSONSerialization.data(withJSONObject: replyObject)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let request = try decoder.decode(AppleCompanionWireMessage.self, from: requestData)
        let reply = try decoder.decode(AppleCompanionWireMessage.self, from: replyData)

        #expect(
            try JSONSerialization.jsonObject(with: encoder.encode(request)) as? NSDictionary
                == requestObject as? NSDictionary
        )
        #expect(
            try JSONSerialization.jsonObject(with: encoder.encode(reply)) as? NSDictionary
                == replyObject as? NSDictionary
        )
    }

    @Test("Discovery correlates replies by request ID and generation")
    func requestCorrelation() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let discovery = Task { try await session.discover() }
        let request = try await transport.waitForRequest()
        #expect(request.operation == .discover)
        let targets = [AppleCompanionTarget(id: "fixture", name: "Living Room")]
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: request.id,
                    generation: request.generation,
                    state: .dormant,
                    targets: targets
                )
            )
        )

        #expect(try await discovery.value == targets)
        #expect(await session.state == .dormant)
    }

    @Test("Concurrent starts share one in-flight connection attempt")
    func concurrentStartIsSingleFlight() async throws {
        let factory = SuspendingTransportFactory(transport: FakeTransport())
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            transportFactory: { await factory.make() }
        )

        let first = Task { try await session.start() }
        await factory.waitUntilRequested()
        let second = Task { try await session.start() }
        await Task.yield()
        await factory.release()
        try await first.value
        try await second.value

        #expect(await factory.requestCount == 1)
        await session.stop()
    }

    @Test("Pairing is two-stage and persists the complete secret")
    func pairingFlow() async throws {
        let transport = FakeTransport()
        let keychain = FakeKeychain()
        let session = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let begin = Task { try await session.beginPairing(targetID: "fixture") }
        let beginRequest = try await transport.waitForRequest()
        #expect(beginRequest.operation == .beginPairing(targetID: "fixture"))
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value
        #expect(await session.state == .pairingRequired)

        let finish = Task { try await session.finishPairing(pin: 1234) }
        let finishRequest = try await transport.waitForRequest()
        #expect(finishRequest.operation == .finishPairing(pin: 1234))
        let secret = AppleCompanionConnectionSecret(
            host: "fixture-host",
            identifier: "fixture-id",
            credentials: "opaque-credential"
        )
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation, .relativeVolume],
                    secret: secret
                )
            )
        )
        _ = try await finish.value

        #expect(try await session.storedSecret() == secret)
        #expect(await session.state == .ready([.navigation, .relativeVolume]))
        #expect(secret.description.contains("opaque-credential") == false)
    }

    @Test("Stored secrets resume without file-backed helper storage")
    func storedSecretResume() async throws {
        let transport = FakeTransport()
        let keychain = FakeKeychain()
        let secret = AppleCompanionConnectionSecret(
            host: "fixture-host",
            identifier: nil,
            credentials: "opaque-credential"
        )
        try keychain.write(try JSONEncoder().encode(secret), account: "primary")
        let session = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let resume = Task { try await session.resume() }
        let request = try await transport.waitForRequest()
        #expect(request.operation == .connect(secret))
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: request.id,
                    generation: request.generation,
                    state: .ready,
                    capabilities: [.navigation]
                )
            )
        )
        _ = try await resume.value
        #expect(await session.state == .ready([.navigation]))
    }

    @Test("Generation invalidation fails pending work and ignores stale replies")
    func staleReplyInvalidation() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let requestTask = Task { try await session.discover() }
        let request = try await transport.waitForRequest()
        await session.invalidate()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: request.id,
                    generation: request.generation,
                    state: .dormant
                )
            )
        )

        do {
            _ = try await requestTask.value
            Issue.record("Invalidated request unexpectedly succeeded")
        } catch let error as AppleCompanionProtocolError {
            #expect(error == .generationInvalidated)
        }
        await session.stop()
    }

    @Test("Paired credentials resume in a new session")
    func pairedCredentialResumesInNewSession() async throws {
        let keychain = FakeKeychain()
        let pairingTransport = FakeTransport()
        let pairingSession = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            transportFactory: { pairingTransport }
        )

        let begin = Task { try await pairingSession.beginPairing(targetID: "fixture") }
        let beginRequest = try await pairingTransport.waitForRequest()
        try await pairingTransport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value

        let secret = AppleCompanionConnectionSecret(
            host: "fixture-host",
            identifier: "fixture-id",
            credentials: "opaque-credential"
        )
        let finish = Task { try await pairingSession.finishPairing(pin: 1234) }
        let finishRequest = try await pairingTransport.waitForRequest()
        try await pairingTransport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation],
                    secret: secret
                )
            )
        )
        _ = try await finish.value
        await pairingSession.stop()

        let resumeTransport = FakeTransport()
        let resumedSession = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            transportFactory: { resumeTransport }
        )
        let resume = Task { try await resumedSession.resume() }
        let resumeRequest = try await resumeTransport.waitForRequest()
        #expect(resumeRequest.operation == .connect(secret))
        try await resumeTransport.push(
            .reply(
                AppleCompanionReply(
                    id: resumeRequest.id,
                    generation: resumeRequest.generation,
                    state: .ready,
                    capabilities: [.navigation]
                )
            )
        )
        _ = try await resume.value

        #expect(await resumedSession.state == .ready([.navigation]))
        await resumedSession.stop()
    }

    @Test("Pairing does not report ready before credential persistence succeeds")
    func pairingCredentialFailureDoesNotReportReady() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FailingWriteKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let begin = Task { try await session.beginPairing(targetID: "fixture") }
        let beginRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value

        let finish = Task { try await session.finishPairing(pin: 1234) }
        let finishRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation],
                    secret: AppleCompanionConnectionSecret(
                        host: "fixture-host",
                        identifier: "fixture-id",
                        credentials: "opaque-credential"
                    )
                )
            )
        )

        await #expect(throws: AppleCompanionKeychainError.unavailable) {
            _ = try await finish.value
        }
        #expect(await session.state == .pairingRequired)
        await session.stop()
    }

    @Test("A pairing reply without credentials is not retained for retry")
    func pairingReplyWithoutCredential() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let begin = Task { try await session.beginPairing(targetID: "fixture") }
        let beginRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value

        let finish = Task { try await session.finishPairing(pin: 1234) }
        let finishRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation]
                )
            )
        )

        await #expect(throws: AppleCompanionKeychainError.invalidData) {
            _ = try await finish.value
        }
        #expect(await session.state == .pairingRequired)
        await #expect(throws: AppleCompanionKeychainError.invalidData) {
            _ = try await session.retryPersistingPairingCredential()
        }
        await session.stop()
    }

    @Test("Pairing credential persistence can be retried without pairing again")
    func pairingCredentialPersistenceRetry() async throws {
        let transport = FakeTransport()
        let keychain = RecoveringWriteKeychain()
        let session = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let begin = Task { try await session.beginPairing(targetID: "fixture") }
        let beginRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value

        let secret = AppleCompanionConnectionSecret(
            host: "fixture-host",
            identifier: "fixture-id",
            credentials: "opaque-credential"
        )
        let finish = Task { try await session.finishPairing(pin: 1234) }
        let finishRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation],
                    secret: secret
                )
            )
        )
        await #expect(throws: AppleCompanionKeychainError.unavailable) {
            _ = try await finish.value
        }
        #expect(await session.state == .pairingRequired)

        _ = try await session.retryPersistingPairingCredential()

        #expect(try await session.storedSecret() == secret)
        #expect(await session.state == .ready([.navigation]))
        await session.stop()
    }

    @Test("Pairing credential retry does not restore stale ready state")
    func pairingCredentialRetryAfterDisconnect() async throws {
        let transport = FakeTransport()
        let keychain = RecoveringWriteKeychain()
        let session = AppleCompanionSession(
            keychain: keychain,
            timeoutNanoseconds: 500_000_000,
            maximumReconnectAttempts: 0,
            transportFactory: { transport }
        )

        let begin = Task { try await session.beginPairing(targetID: "fixture") }
        let beginRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: beginRequest.id,
                    generation: beginRequest.generation,
                    state: .pairingRequired
                )
            )
        )
        try await begin.value

        let secret = AppleCompanionConnectionSecret(
            host: "fixture-host",
            identifier: "fixture-id",
            credentials: "opaque-credential"
        )
        let finish = Task { try await session.finishPairing(pin: 1234) }
        let finishRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: finishRequest.id,
                    generation: finishRequest.generation,
                    state: .ready,
                    capabilities: [.navigation],
                    secret: secret
                )
            )
        )
        await #expect(throws: AppleCompanionKeychainError.unavailable) {
            _ = try await finish.value
        }
        transport.close()
        #expect(await eventually { await session.state == .offline })

        await #expect(throws: AppleCompanionProtocolError.generationInvalidated) {
            _ = try await session.retryPersistingPairingCredential()
        }

        #expect(try await session.storedSecret() == secret)
        #expect(await session.state == .offline)
        await session.stop()
    }

    @Test("Session times out without accepting a late reply")
    func timeout() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 10_000_000,
            transportFactory: { transport }
        )

        let requestTask = Task { try await session.discover() }
        let request = try await transport.waitForRequest()
        do {
            _ = try await requestTask.value
            Issue.record("Timed out request unexpectedly succeeded")
        } catch let error as AppleCompanionProtocolError {
            #expect(error == .timeout)
        }
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: request.id,
                    generation: request.generation,
                    state: .dormant
                )
            )
        )
        await session.stop()
    }

    @Test("Remote errors stay typed and privacy-safe")
    func remoteError() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let requestTask = Task { try await session.discover() }
        let request = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: request.id,
                    generation: request.generation,
                    state: .offline,
                    error: .offline
                )
            )
        )
        do {
            _ = try await requestTask.value
            Issue.record("Remote error unexpectedly succeeded")
        } catch let error as AppleCompanionProtocolError {
            #expect(error == .remote(.offline))
        }
    }

    @Test("Peer loss reconnects and refreshes helper state")
    func reconnectAfterPeerLoss() async throws {
        let firstTransport = FakeTransport()
        let secondTransport = FakeTransport()
        let factory = FakeTransportFactory(transports: [firstTransport, secondTransport])
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { try await factory.next() }
        )

        try await session.start()
        firstTransport.close()
        let statusRequest = try await secondTransport.waitForRequest()
        #expect(statusRequest.operation == .status)
        try await secondTransport.push(
            .reply(
                AppleCompanionReply(
                    id: statusRequest.id,
                    generation: statusRequest.generation,
                    state: .dormant
                )
            )
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await session.state == .dormant)
        await session.stop()
    }

    @Test("Repeated startup failure opens the reconnect circuit")
    func reconnectCircuitBreaker() async {
        let factory = AlwaysFailingTransportFactory()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 20_000_000,
            reconnectBaseDelayNanoseconds: 1_000_000,
            maximumReconnectAttempts: 2,
            transportFactory: { try await factory.make() }
        )

        do {
            try await session.start()
            Issue.record("Failing transport unexpectedly started")
        } catch {}
        #expect(await eventually {
            let requestCount = await factory.requestCount
            let state = await session.state
            return requestCount == 3 && state == .offline
        })
        let attemptsAfterCircuit = await factory.requestCount
        #expect(attemptsAfterCircuit == 3)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(await factory.requestCount == attemptsAfterCircuit)
        await session.stop()

        do {
            try await session.start()
            Issue.record("Failing transport unexpectedly restarted")
        } catch {}
        #expect(await eventually {
            let requestCount = await factory.requestCount
            let state = await session.state
            return requestCount == attemptsAfterCircuit + 3 && state == .offline
        })
        #expect(await factory.requestCount == attemptsAfterCircuit + 3)
        await session.stop()
    }

    @Test("Connection secrets redact normal and reflected descriptions")
    func connectionSecretDescriptionsAreRedacted() {
        let secret = AppleCompanionConnectionSecret(
            host: "private-host",
            identifier: "private-identifier",
            credentials: "private-credentials"
        )

        #expect(String(describing: secret) == "<redacted Apple Companion connection secret>")
        #expect(String(reflecting: secret) == "<redacted Apple Companion connection secret>")
    }

    @Test("Unsupported actions never reach the helper")
    func unsupportedAction() async throws {
        let transport = FakeTransport()
        let session = AppleCompanionSession(
            keychain: FakeKeychain(),
            timeoutNanoseconds: 500_000_000,
            transportFactory: { transport }
        )

        let status = Task { try await session.resume() }
        let statusRequest = try await transport.waitForRequest()
        try await transport.push(
            .reply(
                AppleCompanionReply(
                    id: statusRequest.id,
                    generation: statusRequest.generation,
                    state: .ready,
                    capabilities: [.navigation]
                )
            )
        )
        _ = try await status.value

        do {
            _ = try await session.execute(.playPause)
            Issue.record("Unsupported action unexpectedly succeeded")
        } catch let error as AppleCompanionProtocolError {
            #expect(error == .remote(.unsupportedAction))
        }
        #expect(transport.pendingRequestCount == 0)
    }
}

private final class FakeTransport: AppleCompanionTransport, @unchecked Sendable {
    let incoming: AsyncThrowingStream<Data, Error>
    private let incomingContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let requestStream: AsyncStream<AppleCompanionRequest>
    private let requestContinuation: AsyncStream<AppleCompanionRequest>.Continuation
    private let lock = NSLock()
    private var requestCount = 0

    var pendingRequestCount: Int {
        lock.withLock { requestCount }
    }

    init() {
        var incomingContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        incoming = AsyncThrowingStream { incomingContinuation = $0 }
        self.incomingContinuation = incomingContinuation
        var requestContinuation: AsyncStream<AppleCompanionRequest>.Continuation!
        requestStream = AsyncStream { requestContinuation = $0 }
        self.requestContinuation = requestContinuation
    }

    func start() async throws {}

    func send(_ data: Data) async throws {
        var codec = AppleCompanionFrameCodec()
        guard case let .request(request) = try codec.append(data).first else {
            Issue.record("Fake peer received a non-request frame")
            return
        }
        lock.withLock { requestCount += 1 }
        requestContinuation.yield(request)
    }

    func close() {
        incomingContinuation.finish()
        requestContinuation.finish()
    }

    func waitForRequest() async throws -> AppleCompanionRequest {
        var iterator = requestStream.makeAsyncIterator()
        guard let request = await iterator.next() else {
            throw AppleCompanionProtocolError.connectionLost
        }
        lock.withLock { requestCount -= 1 }
        return request
    }

    func push(_ message: AppleCompanionWireMessage) async throws {
        incomingContinuation.yield(try AppleCompanionFrameCodec().encode(message))
    }
}

private actor FakeTransportFactory {
    private var transports: [FakeTransport]

    init(transports: [FakeTransport]) {
        self.transports = transports
    }

    func next() throws -> FakeTransport {
        guard !transports.isEmpty else {
            throw AppleCompanionProtocolError.unavailable
        }
        return transports.removeFirst()
    }
}

private actor SuspendingTransportFactory {
    private let transport: FakeTransport
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    init(transport: FakeTransport) {
        self.transport = transport
    }

    func make() async -> FakeTransport {
        requestCount += 1
        requestContinuation?.resume()
        requestContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return transport
    }

    func waitUntilRequested() async {
        guard requestCount == 0 else { return }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor AlwaysFailingTransportFactory {
    private(set) var requestCount = 0

    func make() throws -> FakeTransport {
        requestCount += 1
        throw AppleCompanionProtocolError.unavailable
    }
}

private func eventually(
    attempts: Int = 200,
    condition: () async -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await condition()
}

private enum FakeKeychainBucket: Equatable {
    case current
    case legacy
}

private final class FakeKeychainSecurity: AppleCompanionKeychainSecurity, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCurrentData: Data?
    private var storedLegacyData: Data?
    private var storedReadBuckets: [FakeKeychainBucket] = []
    private let legacyReadStatus: OSStatus
    private let addStatus: OSStatus
    private let legacyDeleteStatus: OSStatus

    init(
        currentData: Data? = nil,
        legacyData: Data? = nil,
        legacyReadStatus: OSStatus = errSecSuccess,
        addStatus: OSStatus = errSecSuccess,
        legacyDeleteStatus: OSStatus = errSecSuccess
    ) {
        storedCurrentData = currentData
        storedLegacyData = legacyData
        self.legacyReadStatus = legacyReadStatus
        self.addStatus = addStatus
        self.legacyDeleteStatus = legacyDeleteStatus
    }

    var currentData: Data? {
        lock.withLock { storedCurrentData }
    }

    var legacyData: Data? {
        lock.withLock { storedLegacyData }
    }

    var readBuckets: [FakeKeychainBucket] {
        lock.withLock { storedReadBuckets }
    }

    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, result: Any?) {
        lock.withLock {
            let bucket = bucket(for: query)
            storedReadBuckets.append(bucket)
            if bucket == .legacy, legacyReadStatus != errSecSuccess {
                return (legacyReadStatus, nil)
            }
            let data = bucket == .legacy ? storedLegacyData : storedCurrentData
            return data.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
        }
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            guard bucket(for: query) == .current, storedCurrentData != nil else {
                return errSecItemNotFound
            }
            storedCurrentData = data(in: attributes)
            return errSecSuccess
        }
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            guard addStatus == errSecSuccess else { return addStatus }
            storedCurrentData = data(in: attributes)
            return errSecSuccess
        }
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        lock.withLock {
            switch bucket(for: query) {
            case .current:
                guard storedCurrentData != nil else { return errSecItemNotFound }
                storedCurrentData = nil
                return errSecSuccess
            case .legacy:
                guard storedLegacyData != nil else { return errSecItemNotFound }
                guard legacyDeleteStatus == errSecSuccess else { return legacyDeleteStatus }
                storedLegacyData = nil
                return errSecSuccess
            }
        }
    }

    private func bucket(for query: CFDictionary) -> FakeKeychainBucket {
        let dictionary = query as NSDictionary
        return dictionary[kSecUseDataProtectionKeychain] as? Bool == true ? .legacy : .current
    }

    private func data(in attributes: CFDictionary) -> Data? {
        (attributes as NSDictionary)[kSecValueData] as? Data
    }
}

private final class FakeKeychain: AppleCompanionKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func write(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func delete(account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}

private struct FailingWriteKeychain: AppleCompanionKeychain, Sendable {
    func read(account: String) throws -> Data? {
        nil
    }

    func write(_ data: Data, account: String) throws {
        throw AppleCompanionKeychainError.unavailable
    }

    func delete(account: String) throws {}
}

private final class RecoveringWriteKeychain: AppleCompanionKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    private var shouldFailWrite = true

    func read(account: String) throws -> Data? {
        lock.withLock { value }
    }

    func write(_ data: Data, account: String) throws {
        try lock.withLock {
            if shouldFailWrite {
                shouldFailWrite = false
                throw AppleCompanionKeychainError.unavailable
            }
            value = data
        }
    }

    func delete(account: String) throws {
        lock.withLock { value = nil }
    }
}
