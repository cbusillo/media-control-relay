import Foundation

public enum RelayTargetKind: String, Codable, Equatable, Sendable {
    case preview
}

public struct RelayTargetMetadata: Codable, Equatable, Sendable {
    public let kind: RelayTargetKind
    public let name: String

    public init(kind: RelayTargetKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

public struct RelayConfiguration: Codable, Equatable, Sendable {
    public let target: RelayTargetMetadata
    public let activationRule: ActivationRule

    public init(
        target: RelayTargetMetadata,
        activationRule: ActivationRule
    ) {
        self.target = target
        self.activationRule = activationRule
    }
}

public enum RelayConfigurationFactory {
    public static func preview(for route: RouteSnapshot) -> RelayConfiguration? {
        guard let audioOutputName = usableText(route.audioOutput?.name) else {
            return nil
        }

        let displayName: String?
        let requiresDisplay: Bool
        if route.audioOutput?.transportKind == .display,
           let relatedDisplayName = route.displays.compactMap({
               usableText($0.name)
           }).first(where: {
               namesAreRelated(audioOutputName, $0)
           }) {
            displayName = relatedDisplayName
            requiresDisplay = true
        } else {
            displayName = nil
            requiresDisplay = false
        }

        return RelayConfiguration(
            target: RelayTargetMetadata(
                kind: .preview,
                name: audioOutputName
            ),
            activationRule: ActivationRule(
                audioOutputMatch: audioOutputName,
                displayMatch: displayName,
                requiresDisplay: requiresDisplay
            )
        )
    }

    private static func usableText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func namesAreRelated(_ first: String, _ second: String) -> Bool {
        let foldedFirst = first.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        let foldedSecond = second.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        return foldedFirst.contains(foldedSecond) || foldedSecond.contains(foldedFirst)
    }
}
