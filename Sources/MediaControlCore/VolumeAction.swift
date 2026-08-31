import Foundation

public enum VolumeAction: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case up
    case down
    case mute

    public var supportsHoldRepeat: Bool {
        self != .mute
    }
}
