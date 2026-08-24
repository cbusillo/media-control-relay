import Foundation

public enum VolumeAction: String, CaseIterable, Codable, Equatable, Sendable {
    case up
    case down
    case mute

    public var supportsHoldRepeat: Bool {
        self != .mute
    }
}
