import Foundation
import Network
import Darwin

public protocol AppleCompanionTransport: AnyObject, Sendable {
    var incoming: AsyncThrowingStream<Data, Error> { get }

    func start() async throws
    func send(_ data: Data) async throws
    func close()
}

public final class AppleCompanionUnixSocketTransport: AppleCompanionTransport, @unchecked Sendable {
    public let incoming: AsyncThrowingStream<Data, Error>

    private let path: String
    private let connection: NWConnection
    private let connectTimeoutNanoseconds: UInt64
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let queue = DispatchQueue(label: "com.shinycomputers.media-control-relay.apple-companion")
    private let lock = NSLock()
    private var isClosed = false

    public init(path: String, connectTimeoutNanoseconds: UInt64 = 2_000_000_000) {
        self.path = path
        self.connectTimeoutNanoseconds = connectTimeoutNanoseconds
        self.connection = NWConnection(to: .unix(path: path), using: .tcp)
        var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.incoming = AsyncThrowingStream { streamContinuation = $0 }
        self.continuation = streamContinuation
    }

    public func start() async throws {
        try validateSocket()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready where gate.claim():
                    continuation.resume()
                    self.receiveNext()
                case let .failed(error) where gate.claim():
                    continuation.resume(throwing: error)
                case .waiting where gate.claim():
                    self.connection.cancel()
                    continuation.resume(throwing: AppleCompanionProtocolError.unavailable)
                case .cancelled where gate.claim():
                    continuation.resume(throwing: AppleCompanionProtocolError.connectionLost)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(
                deadline: .now() + .nanoseconds(Int(clamping: connectTimeoutNanoseconds))
            ) {
                guard gate.claim() else { return }
                self.connection.cancel()
                continuation.resume(throwing: AppleCompanionProtocolError.timeout)
            }
        }
    }

    public func send(_ data: Data) async throws {
        guard !lock.withLock({ isClosed }) else {
            throw AppleCompanionProtocolError.connectionLost
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func close() {
        let shouldClose = lock.withLock {
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
        guard shouldClose else { return }
        connection.cancel()
        continuation.finish()
    }

    private func receiveNext() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: AppleCompanionFrameCodec.maximumFrameBytes + 1
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.continuation.yield(data)
            }
            if let error {
                self.continuation.finish(throwing: error)
            } else if isComplete {
                self.continuation.finish()
            } else if !self.lock.withLock({ self.isClosed }) {
                self.receiveNext()
            }
        }
    }

    private func validateSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0 else {
            throw AppleCompanionProtocolError.unavailable
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
