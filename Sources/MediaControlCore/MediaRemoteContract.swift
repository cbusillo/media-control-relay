import Foundation

public enum MediaRemoteDirection: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case up
    case down
    case left
    case right
}

public enum MediaRemoteAction: Equatable, Hashable, Sendable {
    case navigate(MediaRemoteDirection)
    case select
    case back
    case home
    case playPause
    case previous
    case next
    case seek(Int)
    case volume(Int)

    public var requiredCapability: MediaRemoteCapability {
        switch self {
        case .navigate:
            return .navigation
        case .select:
            return .select
        case .back:
            return .back
        case .home:
            return .home
        case .playPause:
            return .playPause
        case .previous:
            return .previous
        case .next:
            return .next
        case .seek:
            return .relativeSeek
        case .volume:
            return .relativeVolume
        }
    }
}

public enum MediaRemoteCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case navigation
    case select
    case back
    case home
    case playPause
    case previous
    case next
    case relativeSeek
    case relativeVolume

}

public enum MediaRemoteFailure: Error, Equatable, Sendable {
    case unconfigured
    case pairingRequired
    case connecting
    case unsupported
    case offline
    case unsupportedAction(MediaRemoteAction)
    case queueFull
    case generationInvalidated
}

public enum MediaRemoteTargetState: Equatable, Sendable {
    case unconfigured
    case pairingRequired
    case connecting
    case ready(capabilities: Set<MediaRemoteCapability>)
    case unsupported
    case offline

    public var capabilities: Set<MediaRemoteCapability> {
        guard case let .ready(capabilities) = self else {
            return []
        }
        return capabilities
    }

    public var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    public func supports(_ action: MediaRemoteAction) -> Bool {
        isReady && capabilities.contains(action.requiredCapability)
    }

    public func require(_ action: MediaRemoteAction) throws(MediaRemoteFailure) {
        switch self {
        case .unconfigured:
            throw .unconfigured
        case .pairingRequired:
            throw .pairingRequired
        case .connecting:
            throw .connecting
        case .unsupported:
            throw .unsupported
        case .offline:
            throw .offline
        case .ready:
            guard supports(action) else {
                throw .unsupportedAction(action)
            }
        }
    }
}

public struct MediaRemoteCommandQueue: Equatable, Sendable {
    public let capacity: Int
    public let maximumSeekMagnitude: Int
    public let maximumVolumeMagnitude: Int

    public private(set) var generation: UInt64
    private var actions: [MediaRemoteAction]

    public init(
        capacity: Int = 32,
        maximumSeekMagnitude: Int = 60,
        maximumVolumeMagnitude: Int = 24,
        generation: UInt64 = 0
    ) {
        self.capacity = max(1, capacity)
        self.maximumSeekMagnitude = max(1, maximumSeekMagnitude)
        self.maximumVolumeMagnitude = max(1, maximumVolumeMagnitude)
        self.generation = generation
        self.actions = []
    }

    public var pendingCount: Int {
        actions.count
    }

    public var isEmpty: Bool {
        actions.isEmpty
    }

    public var pendingActions: [MediaRemoteAction] {
        actions
    }

    public mutating func enqueue(
        _ action: MediaRemoteAction,
        generation expectedGeneration: UInt64? = nil
    ) throws(MediaRemoteFailure) {
        if let expectedGeneration, expectedGeneration != generation {
            throw .generationInvalidated
        }

        guard let boundedAction = bounded(action) else {
            return
        }

        if coalesce(boundedAction) {
            return
        }

        guard actions.count < capacity else {
            throw .queueFull
        }
        actions.append(boundedAction)
    }

    public mutating func dequeue() -> MediaRemoteAction? {
        guard !actions.isEmpty else {
            return nil
        }
        return actions.removeFirst()
    }

    @discardableResult
    public mutating func invalidate() -> UInt64 {
        generation &+= 1
        actions.removeAll(keepingCapacity: true)
        return generation
    }

    private func bounded(_ action: MediaRemoteAction) -> MediaRemoteAction? {
        switch action {
        case let .seek(delta):
            let boundedDelta = clamp(delta, to: maximumSeekMagnitude)
            return boundedDelta == 0 ? nil : .seek(boundedDelta)
        case let .volume(delta):
            let boundedDelta = clamp(delta, to: maximumVolumeMagnitude)
            return boundedDelta == 0 ? nil : .volume(boundedDelta)
        default:
            return action
        }
    }

    private mutating func coalesce(_ action: MediaRemoteAction) -> Bool {
        guard let last = actions.last else {
            return false
        }

        let combined: MediaRemoteAction?
        switch (last, action) {
        case let (.seek(existing), .seek(delta)):
            combined = combinedDelta(
                existing,
                delta,
                maximumMagnitude: maximumSeekMagnitude
            ).map(MediaRemoteAction.seek)
        case let (.volume(existing), .volume(delta)):
            combined = combinedDelta(
                existing,
                delta,
                maximumMagnitude: maximumVolumeMagnitude
            ).map(MediaRemoteAction.volume)
        default:
            return false
        }

        if let combined {
            actions[actions.index(before: actions.endIndex)] = combined
        } else {
            actions.removeLast()
        }
        return true
    }

    private func combinedDelta(
        _ lhs: Int,
        _ rhs: Int,
        maximumMagnitude: Int
    ) -> Int? {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        let boundedSum: Int
        if overflow {
            boundedSum = lhs >= 0 ? Int.max : Int.min
        } else {
            boundedSum = sum
        }

        let result = clamp(boundedSum, to: maximumMagnitude)
        return result == 0 ? nil : result
    }

    private func clamp(_ value: Int, to maximumMagnitude: Int) -> Int {
        min(max(value, -maximumMagnitude), maximumMagnitude)
    }
}
