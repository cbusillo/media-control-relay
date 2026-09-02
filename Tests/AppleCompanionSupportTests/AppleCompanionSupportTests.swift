import Foundation
import MediaControlCore
import Testing
@testable import AppleCompanionSupport

@Suite("Apple Companion support", .serialized)
struct AppleCompanionSupportTests {
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
