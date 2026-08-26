import Foundation
import MediaControlCore

enum UPnPMediaTargetIdentityParser {
    static func parse(_ value: String) -> MediaTargetIdentity? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 5,
              trimmed.prefix(5).lowercased() == "uuid:",
              trimmed.utf8.allSatisfy({ (33...126).contains($0) }) else {
            return nil
        }
        return MediaTargetIdentity(stableIdentifier: trimmed.lowercased())
    }
}
