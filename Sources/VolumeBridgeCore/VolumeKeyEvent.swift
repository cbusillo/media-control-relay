import Foundation

public enum VolumeKeyPhase: Sendable, Equatable {
    case pressed
    case released
}

public struct VolumeKeyEvent: Sendable, Equatable {
    public let action: VolumeAction
    public let phase: VolumeKeyPhase
    public let isRepeat: Bool
    public let timestamp: TimeInterval

    public init(
        action: VolumeAction,
        phase: VolumeKeyPhase,
        isRepeat: Bool,
        timestamp: TimeInterval
    ) {
        self.action = action
        self.phase = phase
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}
