import Foundation
import MediaControlCore

enum ExternalVolumeActionURLParser {
    private static let scheme = "media-control-relay"
    private static let host = "control"
    private static let canonicalActions: [String: VolumeAction] = [
        "media-control-relay://control/volume/up": .up,
        "media-control-relay://control/volume/down": .down,
        "media-control-relay://control/volume/mute": .mute,
    ]

    static func action(for url: URL) -> VolumeAction? {
        guard url.scheme == scheme,
              url.host == host,
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.hasPrefix("/volume/") else {
            return nil
        }

        return canonicalActions[url.absoluteString]
    }
}
