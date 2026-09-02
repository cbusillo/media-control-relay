import Foundation
import MediaControlCore

public enum AppleCompanionRemoteErrorCode: String, Codable, Equatable, Sendable {
    case malformedRequest
    case oversizedFrame
    case unavailable
    case offline
    case pairingRequired
    case pairingFailed
    case unsupportedAction
}

public enum AppleCompanionProtocolError: Error, Equatable, Sendable {
    case malformedFrame
    case oversizedFrame
    case invalidMessage
    case connectionLost
    case timeout
    case generationInvalidated
    case unavailable
    case remote(AppleCompanionRemoteErrorCode)
}

public struct AppleCompanionTarget: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AppleCompanionConnectionSecret: Codable, Equatable, Sendable {
    public let host: String
    public let identifier: String?
    public let credentials: String

    public init(host: String, identifier: String?, credentials: String) {
        self.host = host
        self.identifier = identifier
        self.credentials = credentials
    }
}

extension AppleCompanionConnectionSecret: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "<redacted Apple Companion connection secret>" }
    public var debugDescription: String { description }
}

public enum AppleCompanionOperation: Codable, Equatable, Sendable {
    case discover
    case beginPairing(targetID: String)
    case finishPairing(pin: Int)
    case connect(AppleCompanionConnectionSecret)
    case status
    case action(AppleCompanionAction)
    case disconnect

    private enum CodingKeys: String, CodingKey {
        case operation
        case targetID
        case pin
        case secret
        case action
    }

    private enum OperationName: String, Codable {
        case discover
        case beginPairing
        case finishPairing
        case connect
        case status
        case action
        case disconnect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OperationName.self, forKey: .operation) {
        case .discover:
            self = .discover
        case .beginPairing:
            self = .beginPairing(targetID: try container.decode(String.self, forKey: .targetID))
        case .finishPairing:
            self = .finishPairing(pin: try container.decode(Int.self, forKey: .pin))
        case .connect:
            self = .connect(try container.decode(AppleCompanionConnectionSecret.self, forKey: .secret))
        case .status:
            self = .status
        case .action:
            self = .action(try container.decode(AppleCompanionAction.self, forKey: .action))
        case .disconnect:
            self = .disconnect
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .discover:
            try container.encode(OperationName.discover, forKey: .operation)
        case let .beginPairing(targetID):
            try container.encode(OperationName.beginPairing, forKey: .operation)
            try container.encode(targetID, forKey: .targetID)
        case let .finishPairing(pin):
            try container.encode(OperationName.finishPairing, forKey: .operation)
            try container.encode(pin, forKey: .pin)
        case let .connect(secret):
            try container.encode(OperationName.connect, forKey: .operation)
            try container.encode(secret, forKey: .secret)
        case .status:
            try container.encode(OperationName.status, forKey: .operation)
        case let .action(action):
            try container.encode(OperationName.action, forKey: .operation)
            try container.encode(action, forKey: .action)
        case .disconnect:
            try container.encode(OperationName.disconnect, forKey: .operation)
        }
    }
}

public enum AppleCompanionAction: Codable, Equatable, Sendable {
    case navigate(MediaRemoteDirection)
    case select
    case back
    case home
    case playPause
    case previous
    case next
    case relativeSeek(Int)
    case relativeVolume(Int)

    private enum CodingKeys: String, CodingKey {
        case action
        case direction
        case delta
    }

    private enum ActionName: String, Codable {
        case navigate
        case select
        case back
        case home
        case playPause
        case previous
        case next
        case relativeSeek
        case relativeVolume
    }

    public init(_ action: MediaRemoteAction) {
        switch action {
        case let .navigate(direction): self = .navigate(direction)
        case .select: self = .select
        case .back: self = .back
        case .home: self = .home
        case .playPause: self = .playPause
        case .previous: self = .previous
        case .next: self = .next
        case let .seek(delta): self = .relativeSeek(delta)
        case let .volume(delta): self = .relativeVolume(delta)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionName.self, forKey: .action) {
        case .navigate: self = .navigate(try container.decode(MediaRemoteDirection.self, forKey: .direction))
        case .select: self = .select
        case .back: self = .back
        case .home: self = .home
        case .playPause: self = .playPause
        case .previous: self = .previous
        case .next: self = .next
        case .relativeSeek: self = .relativeSeek(try container.decode(Int.self, forKey: .delta))
        case .relativeVolume: self = .relativeVolume(try container.decode(Int.self, forKey: .delta))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .navigate(direction):
            try container.encode(ActionName.navigate, forKey: .action)
            try container.encode(direction, forKey: .direction)
        case .select: try container.encode(ActionName.select, forKey: .action)
        case .back: try container.encode(ActionName.back, forKey: .action)
        case .home: try container.encode(ActionName.home, forKey: .action)
        case .playPause: try container.encode(ActionName.playPause, forKey: .action)
        case .previous: try container.encode(ActionName.previous, forKey: .action)
        case .next: try container.encode(ActionName.next, forKey: .action)
        case let .relativeSeek(delta):
            try container.encode(ActionName.relativeSeek, forKey: .action)
            try container.encode(delta, forKey: .delta)
        case let .relativeVolume(delta):
            try container.encode(ActionName.relativeVolume, forKey: .action)
            try container.encode(delta, forKey: .delta)
        }
    }
}

public enum AppleCompanionState: String, Codable, Equatable, Sendable {
    case dormant
    case pairingRequired
    case connecting
    case ready
    case offline
    case unsupported
}

public struct AppleCompanionRequest: Codable, Equatable, Sendable {
    public let id: UInt64
    public let generation: UInt64
    public let operation: AppleCompanionOperation

    public init(id: UInt64, generation: UInt64, operation: AppleCompanionOperation) {
        self.id = id
        self.generation = generation
        self.operation = operation
    }
}

public struct AppleCompanionReply: Codable, Equatable, Sendable {
    public let id: UInt64
    public let generation: UInt64
    public let state: AppleCompanionState
    public let capabilities: Set<MediaRemoteCapability>
    public let targets: [AppleCompanionTarget]
    public let secret: AppleCompanionConnectionSecret?
    public let error: AppleCompanionRemoteErrorCode?

    private enum CodingKeys: String, CodingKey {
        case id
        case generation
        case state
        case capabilities
        case targets
        case secret
        case error
    }

    public init(
        id: UInt64,
        generation: UInt64,
        state: AppleCompanionState,
        capabilities: Set<MediaRemoteCapability> = [],
        targets: [AppleCompanionTarget] = [],
        secret: AppleCompanionConnectionSecret? = nil,
        error: AppleCompanionRemoteErrorCode? = nil
    ) {
        self.id = id
        self.generation = generation
        self.state = state
        self.capabilities = capabilities
        self.targets = targets
        self.secret = secret
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt64.self, forKey: .id)
        generation = try container.decode(UInt64.self, forKey: .generation)
        state = try container.decode(AppleCompanionState.self, forKey: .state)
        capabilities = try container.decode(Set<MediaRemoteCapability>.self, forKey: .capabilities)
        targets = try container.decode([AppleCompanionTarget].self, forKey: .targets)
        secret = try container.decodeIfPresent(AppleCompanionConnectionSecret.self, forKey: .secret)
        error = try container.decodeIfPresent(AppleCompanionRemoteErrorCode.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(generation, forKey: .generation)
        try container.encode(state, forKey: .state)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(targets, forKey: .targets)
        if let secret {
            try container.encode(secret, forKey: .secret)
        } else {
            try container.encodeNil(forKey: .secret)
        }
        if let error {
            try container.encode(error, forKey: .error)
        } else {
            try container.encodeNil(forKey: .error)
        }
    }
}

public enum AppleCompanionWireMessage: Codable, Equatable, Sendable {
    case request(AppleCompanionRequest)
    case reply(AppleCompanionReply)

    private enum CodingKeys: String, CodingKey { case kind, request, reply }
    private enum Kind: String, Codable { case request, reply }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .request: self = .request(try container.decode(AppleCompanionRequest.self, forKey: .request))
        case .reply: self = .reply(try container.decode(AppleCompanionReply.self, forKey: .reply))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .request(request):
            try container.encode(Kind.request, forKey: .kind)
            try container.encode(request, forKey: .request)
        case let .reply(reply):
            try container.encode(Kind.reply, forKey: .kind)
            try container.encode(reply, forKey: .reply)
        }
    }
}

public struct AppleCompanionFrameCodec: Sendable {
    public static let maximumFrameBytes = 16 * 1024

    private var buffer = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public mutating func append(_ data: Data) throws(AppleCompanionProtocolError) -> [AppleCompanionWireMessage] {
        buffer.append(data)
        var messages: [AppleCompanionWireMessage] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let frame = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !frame.isEmpty else { throw .malformedFrame }
            guard frame.count <= Self.maximumFrameBytes else { throw .oversizedFrame }
            do {
                messages.append(try decoder.decode(AppleCompanionWireMessage.self, from: frame))
            } catch {
                throw .malformedFrame
            }
        }
        guard buffer.count <= Self.maximumFrameBytes else { throw .oversizedFrame }
        return messages
    }

    public mutating func finish() throws(AppleCompanionProtocolError) {
        guard buffer.isEmpty else { throw .malformedFrame }
    }

    public func encode(_ message: AppleCompanionWireMessage) throws(AppleCompanionProtocolError) -> Data {
        do {
            let data = try encoder.encode(message) + Data([0x0A])
            guard data.count <= Self.maximumFrameBytes else { throw AppleCompanionProtocolError.oversizedFrame }
            return data
        } catch let error as AppleCompanionProtocolError {
            throw error
        } catch {
            throw .invalidMessage
        }
    }
}
