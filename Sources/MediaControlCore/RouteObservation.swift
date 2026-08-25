import Foundation

public enum AudioTransportKind: String, Equatable, Sendable {
    case airPlay
    case bluetooth
    case builtIn
    case display
    case usb
    case aggregate
    case unknown
}

public struct AudioOutputObservation: Equatable, Sendable {
    public let name: String?
    public let stableIdentifier: String?
    public let transportKind: AudioTransportKind

    public init(
        name: String?,
        stableIdentifier: String? = nil,
        transportKind: AudioTransportKind
    ) {
        self.name = name
        self.stableIdentifier = stableIdentifier
        self.transportKind = transportKind
    }
}

public struct DisplayObservation: Equatable, Sendable {
    public let name: String?
    public let stableIdentifier: String?
    public let isConnected: Bool
    public let isActive: Bool

    public init(
        name: String?,
        stableIdentifier: String? = nil,
        isConnected: Bool = true,
        isActive: Bool = true
    ) {
        self.name = name
        self.stableIdentifier = stableIdentifier
        self.isConnected = isConnected
        self.isActive = isActive
    }
}

public struct AudioOutputSnapshot: Equatable, Sendable {
    public let name: String?
    public let stableIdentifier: String?
    public let transportKind: AudioTransportKind

    public init(
        name: String?,
        stableIdentifier: String? = nil,
        transportKind: AudioTransportKind
    ) {
        self.name = name
        self.transportKind = transportKind
        self.stableIdentifier = stableIdentifier
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public let name: String?
    public let stableIdentifier: String?

    public init(
        name: String?,
        stableIdentifier: String? = nil
    ) {
        self.name = name
        self.stableIdentifier = stableIdentifier
    }
}

public struct RouteSnapshot: Equatable, Sendable {
    public let audioOutput: AudioOutputSnapshot?
    public let displays: [DisplaySnapshot]

    public init(
        audioOutput: AudioOutputSnapshot?,
        displays: [DisplaySnapshot]
    ) {
        self.audioOutput = audioOutput
        self.displays = displays
    }

    public var activationSnapshot: ActivationSnapshot {
        ActivationSnapshot(
            defaultAudioOutputName: audioOutput?.name,
            displayNames: displays.compactMap(\.name)
        )
    }
}

public enum RouteSnapshotNormalizer {
    public static func normalize(
        audioOutput: AudioOutputObservation?,
        displays: [DisplayObservation]
    ) -> RouteSnapshot {
        let normalizedAudioOutput = audioOutput.map {
            AudioOutputSnapshot(
                name: normalizeName($0.name),
                stableIdentifier: normalizeIdentifier($0.stableIdentifier),
                transportKind: $0.transportKind
            )
        }

        var normalizedDisplays: [DisplaySnapshot] = []
        var seenKeys = Set<String>()

        for display in displays where display.isConnected && display.isActive {
            let normalizedDisplay = DisplaySnapshot(
                name: normalizeName(display.name),
                stableIdentifier: normalizeIdentifier(display.stableIdentifier)
            )
            if let key = displayKey(for: normalizedDisplay),
               !seenKeys.insert(key).inserted {
                continue
            }
            normalizedDisplays.append(normalizedDisplay)
        }

        normalizedDisplays.sort { lhs, rhs in
            displaySortKey(lhs) < displaySortKey(rhs)
        }

        return RouteSnapshot(
            audioOutput: normalizedAudioOutput,
            displays: normalizedDisplays
        )
    }

    private static func normalizeName(_ value: String?) -> String? {
        normalizeText(value)
    }

    private static func normalizeIdentifier(_ value: String?) -> String? {
        normalizeText(value)
    }

    private static func normalizeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func displayKey(for display: DisplaySnapshot) -> String? {
        if let stableIdentifier = display.stableIdentifier {
            return "identifier:\(stableIdentifier)"
        }
        guard let name = display.name else {
            return nil
        }
        return "name:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))"
    }

    private static func displaySortKey(_ display: DisplaySnapshot) -> String {
        display.stableIdentifier ?? display.name ?? ""
    }
}

public enum RouteObservationState: String, Equatable, Sendable {
    case stopped
    case observing
    case suspended
}

public enum RouteObservationLifecycleAction: Equatable, Sendable {
    case none
    case registerRouteObserversAndPublishFreshSnapshot
    case unregisterRouteObservers
}

public struct RouteObservationLifecycle: Sendable {
    public private(set) var state: RouteObservationState = .stopped

    public init() {}

    public mutating func start() -> RouteObservationLifecycleAction {
        guard state == .stopped else {
            return .none
        }
        state = .observing
        return .registerRouteObserversAndPublishFreshSnapshot
    }

    public mutating func stop() -> RouteObservationLifecycleAction {
        guard state != .stopped else {
            return .none
        }
        state = .stopped
        return .unregisterRouteObservers
    }

    public mutating func sleep() -> RouteObservationLifecycleAction {
        guard state == .observing else {
            return .none
        }
        state = .suspended
        return .unregisterRouteObservers
    }

    public mutating func wake() -> RouteObservationLifecycleAction {
        guard state == .suspended else {
            return .none
        }
        state = .observing
        return .registerRouteObserversAndPublishFreshSnapshot
    }
}

public enum RouteObservationCoalescerEvent: Equatable, Sendable {
    case ignored
    case publish(RouteSnapshot)
    case scheduled(deadline: TimeInterval)
}

public struct RouteObservationCoalescer: Sendable {
    public let duplicateWindow: TimeInterval

    private var lastPublishedSnapshot: RouteSnapshot?
    private var lastPublishedTimestamp: TimeInterval?
    private var pendingSnapshot: RouteSnapshot?

    public init(duplicateWindow: TimeInterval = 0.1) {
        self.duplicateWindow = max(0, duplicateWindow)
    }

    public mutating func receive(
        _ snapshot: RouteSnapshot,
        at timestamp: TimeInterval
    ) -> RouteObservationCoalescerEvent {
        if snapshot == lastPublishedSnapshot {
            pendingSnapshot = nil
            return .ignored
        }

        if let lastPublishedTimestamp,
           timestamp < lastPublishedTimestamp + duplicateWindow {
            if pendingSnapshot == snapshot {
                return .ignored
            }
            pendingSnapshot = snapshot
            return .scheduled(deadline: lastPublishedTimestamp + duplicateWindow)
        }

        return publish(snapshot, at: timestamp)
    }

    public mutating func flush(
        at timestamp: TimeInterval
    ) -> RouteObservationCoalescerEvent {
        guard let pendingSnapshot,
              let lastPublishedTimestamp else {
            return .ignored
        }
        let deadline = lastPublishedTimestamp + duplicateWindow
        guard timestamp >= deadline else {
            return .scheduled(deadline: deadline)
        }
        return publish(pendingSnapshot, at: timestamp)
    }

    public mutating func reset() {
        lastPublishedSnapshot = nil
        lastPublishedTimestamp = nil
        pendingSnapshot = nil
    }

    private mutating func publish(
        _ snapshot: RouteSnapshot,
        at timestamp: TimeInterval
    ) -> RouteObservationCoalescerEvent {
        lastPublishedSnapshot = snapshot
        lastPublishedTimestamp = timestamp
        pendingSnapshot = nil
        return .publish(snapshot)
    }
}

public struct RouteObservationDiagnostics: Equatable, Sendable {
    public let observationState: RouteObservationState
    public let audioTransportKind: AudioTransportKind?
    public let activeDisplayCount: Int

    public init(
        state: RouteObservationState,
        snapshot: RouteSnapshot
    ) {
        observationState = state
        audioTransportKind = snapshot.audioOutput?.transportKind
        activeDisplayCount = snapshot.displays.count
    }

    public var fields: [String: String] {
        [
            "route_observation": observationState.rawValue,
            "audio_transport": audioTransportKind?.rawValue ?? "none",
            "active_displays": activeDisplayCount.formatted(),
        ]
    }
}
