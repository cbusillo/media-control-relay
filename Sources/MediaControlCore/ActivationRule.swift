import Foundation

public struct ActivationSnapshot: Equatable, Sendable {
    public var defaultAudioOutputName: String?
    public var displayNames: [String]

    public init(
        defaultAudioOutputName: String?,
        displayNames: [String]
    ) {
        self.defaultAudioOutputName = defaultAudioOutputName
        self.displayNames = displayNames
    }

    public init(routeSnapshot: RouteSnapshot) {
        self = routeSnapshot.activationSnapshot
    }
}

public struct ActivationRule: Codable, Equatable, Sendable {
    public var audioOutputMatch: String
    public var displayMatch: String?
    public var requiresDisplay: Bool

    public init(
        audioOutputMatch: String,
        displayMatch: String? = nil,
        requiresDisplay: Bool = true
    ) {
        self.audioOutputMatch = audioOutputMatch
        self.displayMatch = displayMatch
        self.requiresDisplay = requiresDisplay
    }

    public func matches(_ snapshot: ActivationSnapshot) -> Bool {
        guard contains(snapshot.defaultAudioOutputName, expected: audioOutputMatch) else {
            return false
        }
        guard requiresDisplay else {
            return true
        }
        return snapshot.displayNames.contains {
            matchesDisplayName($0)
        }
    }

    public func matchesDisplayName(_ displayName: String?) -> Bool {
        guard let expectedDisplay = normalized(displayMatch) ?? normalized(audioOutputMatch) else {
            return false
        }
        return contains(displayName, expected: expectedDisplay)
    }

    private func contains(_ value: String?, expected: String) -> Bool {
        guard let value, let expected = normalized(expected) else {
            return false
        }
        return value.range(
            of: expected,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
