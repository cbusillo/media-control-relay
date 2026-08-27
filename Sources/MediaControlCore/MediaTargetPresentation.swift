import Foundation

public struct MediaTargetSessionOutcome: Equatable, Sendable {
    public let reachability: TransportReachability
    public let confirmedState: MediaTargetVolumeState?
    public let generation: UInt64

    public init(
        reachability: TransportReachability,
        confirmedState: MediaTargetVolumeState?,
        generation: UInt64
    ) {
        self.reachability = reachability
        self.confirmedState = confirmedState
        self.generation = generation
    }
}

public struct MediaTargetPresentationValue: Equatable, Sendable {
    public let normalizedLevel: Double
    public let confirmedVolume: Int
    public let displayedVolume: Int
    public let isMuted: Bool
    public let minimumVolume: Int
    public let maximumVolume: Int
    public let volumeStep: Int

    public init(
        normalizedLevel: Double,
        confirmedVolume: Int,
        displayedVolume: Int,
        isMuted: Bool,
        minimumVolume: Int,
        maximumVolume: Int,
        volumeStep: Int
    ) {
        self.normalizedLevel = normalizedLevel
        self.confirmedVolume = confirmedVolume
        self.displayedVolume = displayedVolume
        self.isMuted = isMuted
        self.minimumVolume = minimumVolume
        self.maximumVolume = maximumVolume
        self.volumeStep = volumeStep
    }

    public var percentage: Int {
        Int((normalizedLevel * 100).rounded())
    }
}

public enum MediaTargetVolumeNormalizer {
    public static func normalize(
        _ state: MediaTargetVolumeState,
        displayedVolume: Int? = nil
    ) -> MediaTargetPresentationValue? {
        guard state.minimumVolume < state.maximumVolume,
              state.volumeStep > 0,
              state.absoluteVolume >= state.minimumVolume,
              state.absoluteVolume <= state.maximumVolume else {
            return nil
        }

        let displayVolume = state.clamped(displayedVolume ?? state.absoluteVolume)
        let normalizedLevel: Double
        if displayVolume == state.minimumVolume {
            normalizedLevel = 0
        } else if displayVolume == state.maximumVolume {
            normalizedLevel = 1
        } else {
            normalizedLevel = Double(displayVolume - state.minimumVolume) /
                Double(state.maximumVolume - state.minimumVolume)
        }

        return MediaTargetPresentationValue(
            normalizedLevel: normalizedLevel,
            confirmedVolume: state.absoluteVolume,
            displayedVolume: displayVolume,
            isMuted: state.isMuted,
            minimumVolume: state.minimumVolume,
            maximumVolume: state.maximumVolume,
            volumeStep: state.volumeStep
        )
    }
}

public enum MediaTargetPresentationRail: Equatable, Sendable {
    case minimum
    case maximum
}

public enum MediaTargetPresentationInvalidation: Equatable, Sendable {
    case configuration
    case permission
    case session
    case sleep
    case routeMismatch
}

public enum MediaTargetPresentationState: Equatable, Sendable {
    case hidden
    case pendingCold(VolumeAction)
    case pendingBaseline(VolumeAction, MediaTargetPresentationValue)
    case confirmed(MediaTargetPresentationValue)
    case muted(MediaTargetPresentationValue)
    case rail(MediaTargetPresentationRail, MediaTargetPresentationValue)
    case failed(MediaTargetPresentationValue?)
    case suspended
    case routeLost

    public var value: MediaTargetPresentationValue? {
        switch self {
        case let .pendingBaseline(_, value),
             let .confirmed(value),
             let .muted(value),
             let .rail(_, value):
            return value
        case let .failed(value):
            return value
        case .hidden, .pendingCold, .suspended, .routeLost:
            return nil
        }
    }

    public var isVisible: Bool {
        switch self {
        case .hidden, .suspended, .routeLost:
            return false
        case .pendingCold, .pendingBaseline, .confirmed, .muted, .rail, .failed:
            return true
        }
    }
}

public struct MediaTargetPresentationTiming: Equatable, Sendable {
    public let baselineFreshness: TimeInterval
    public let confirmationDisplayDuration: TimeInterval
    public let announcementInterval: TimeInterval

    public init(
        baselineFreshness: TimeInterval = 1,
        confirmationDisplayDuration: TimeInterval = 1.5,
        announcementInterval: TimeInterval = 0.25
    ) {
        self.baselineFreshness = max(0, baselineFreshness)
        self.confirmationDisplayDuration = max(0, confirmationDisplayDuration)
        self.announcementInterval = max(0, announcementInterval)
    }
}

public struct MediaTargetPresentationModel: Equatable, Sendable {
    public private(set) var state: MediaTargetPresentationState = .hidden

    public let timing: MediaTargetPresentationTiming

    public private(set) var invalidationEpoch: UInt64 = 0

    private var newestOutcomeGeneration: UInt64 = 0
    private var pendingAction: VolumeAction?
    private var pendingRequestID: UInt64?
    private var newestRequestID: UInt64 = 0
    private var lastConfirmedValue: MediaTargetPresentationValue?
    private var lastConfirmedAt: TimeInterval?
    private var lastNonzeroConfirmedVolume: Int?
    private var stateSince: TimeInterval?
    private var lastAnnouncementAt: TimeInterval?

    public init(timing: MediaTargetPresentationTiming = MediaTargetPresentationTiming()) {
        self.timing = timing
    }

    @discardableResult
    public mutating func receiveProbe(
        _ outcome: MediaTargetSessionOutcome,
        epoch: UInt64,
        at timestamp: TimeInterval
    ) -> Bool {
        guard epoch == invalidationEpoch,
              outcome.generation >= newestOutcomeGeneration else {
            return false
        }

        newestOutcomeGeneration = outcome.generation
        guard outcome.reachability == .reachable,
              let confirmedState = outcome.confirmedState,
              let value = makePresentationValue(for: confirmedState) else {
            return false
        }

        guard pendingAction == nil else {
            return false
        }
        lastConfirmedValue = value
        lastConfirmedAt = timestamp
        state = stateFor(value: value, action: nil)
        stateSince = timestamp
        return true
    }

    @discardableResult
    public mutating func begin(
        action: VolumeAction,
        requestID: UInt64,
        epoch: UInt64,
        at timestamp: TimeInterval
    ) -> Bool {
        guard epoch == invalidationEpoch,
              requestID > newestRequestID else {
            return false
        }

        newestRequestID = requestID
        pendingAction = action
        pendingRequestID = requestID
        if let lastConfirmedAt,
           timestamp >= lastConfirmedAt,
           timestamp - lastConfirmedAt <= timing.baselineFreshness,
           let lastConfirmedValue {
            state = .pendingBaseline(action, lastConfirmedValue)
        } else {
            state = .pendingCold(action)
        }
        stateSince = timestamp
        return true
    }

    @discardableResult
    public mutating func receive(
        _ outcome: MediaTargetSessionOutcome,
        requestID: UInt64,
        epoch: UInt64,
        at timestamp: TimeInterval
    ) -> Bool {
        guard epoch == invalidationEpoch,
              requestID == pendingRequestID else {
            return false
        }

        newestOutcomeGeneration = max(newestOutcomeGeneration, outcome.generation)
        guard outcome.reachability == .reachable,
              let confirmedState = outcome.confirmedState,
              let value = makePresentationValue(for: confirmedState) else {
            guard pendingAction != nil else {
                return false
            }
            state = .failed(lastConfirmedValue)
            pendingAction = nil
            pendingRequestID = nil
            stateSince = timestamp
            return true
        }

        let action = pendingAction
        lastConfirmedValue = value
        lastConfirmedAt = timestamp
        pendingAction = nil
        pendingRequestID = nil
        state = stateFor(value: value, action: action)
        stateSince = timestamp
        return true
    }

    @discardableResult
    public mutating func fail(
        requestID: UInt64,
        epoch: UInt64,
        at timestamp: TimeInterval
    ) -> Bool {
        guard epoch == invalidationEpoch,
              requestID == pendingRequestID,
              pendingAction != nil else {
            return false
        }

        pendingAction = nil
        pendingRequestID = nil
        state = .failed(lastConfirmedValue)
        stateSince = timestamp
        return true
    }

    @discardableResult
    public mutating func cancel(
        requestID: UInt64,
        epoch: UInt64
    ) -> Bool {
        guard epoch == invalidationEpoch,
              requestID == pendingRequestID else {
            return false
        }

        pendingAction = nil
        pendingRequestID = nil
        state = .hidden
        stateSince = nil
        lastAnnouncementAt = nil
        return true
    }

    public mutating func invalidate(_ reason: MediaTargetPresentationInvalidation) {
        invalidationEpoch &+= 1
        newestOutcomeGeneration = 0
        pendingAction = nil
        pendingRequestID = nil
        lastConfirmedValue = nil
        lastConfirmedAt = nil
        lastNonzeroConfirmedVolume = nil
        lastAnnouncementAt = nil
        switch reason {
        case .sleep:
            state = .suspended
        case .routeMismatch:
            state = .routeLost
        case .configuration, .permission, .session:
            state = .hidden
        }
        stateSince = nil
    }

    public mutating func dismiss() {
        state = .hidden
        stateSince = nil
        lastAnnouncementAt = nil
    }

    @discardableResult
    public mutating func advance(to timestamp: TimeInterval) -> Bool {
        guard state.isVisible,
              let stateSince,
              timestamp >= stateSince,
              timestamp - stateSince >= timing.confirmationDisplayDuration else {
            return false
        }

        state = .hidden
        self.stateSince = nil
        return true
    }

    public mutating func shouldAnnounce(at timestamp: TimeInterval) -> Bool {
        switch state {
        case .confirmed, .muted, .rail:
            break
        case .hidden, .pendingCold, .pendingBaseline, .failed, .suspended, .routeLost:
            return false
        }
        guard let lastAnnouncementAt else {
            self.lastAnnouncementAt = timestamp
            return true
        }
        guard timestamp >= lastAnnouncementAt,
              timestamp - lastAnnouncementAt >= timing.announcementInterval else {
            return false
        }
        self.lastAnnouncementAt = timestamp
        return true
    }

    private mutating func makePresentationValue(
        for state: MediaTargetVolumeState
    ) -> MediaTargetPresentationValue? {
        if state.absoluteVolume > state.minimumVolume {
            lastNonzeroConfirmedVolume = state.absoluteVolume
        }
        let retainedVolume = state.isMuted && state.absoluteVolume == state.minimumVolume
            ? lastNonzeroConfirmedVolume
            : nil
        return MediaTargetVolumeNormalizer.normalize(
            state,
            displayedVolume: retainedVolume
        )
    }

    private func stateFor(
        value: MediaTargetPresentationValue,
        action: VolumeAction?
    ) -> MediaTargetPresentationState {
        if value.isMuted {
            return .muted(value)
        }
        switch action {
        case .up where value.confirmedVolume == value.maximumVolume:
            return .rail(.maximum, value)
        case .down where value.confirmedVolume == value.minimumVolume:
            return .rail(.minimum, value)
        default:
            return .confirmed(value)
        }
    }
}
