import Foundation
import MediaControlCore

enum ExternalRemoteActionURLParser {
    private static let scheme = "media-control-relay"
    private static let host = "remote"

    private static let canonicalActions: [String: MediaRemoteAction] = [
        "media-control-relay://remote/navigate/up": .navigate(.up),
        "media-control-relay://remote/navigate/down": .navigate(.down),
        "media-control-relay://remote/navigate/left": .navigate(.left),
        "media-control-relay://remote/navigate/right": .navigate(.right),
        "media-control-relay://remote/select": .select,
        "media-control-relay://remote/back": .back,
        "media-control-relay://remote/home": .home,
        "media-control-relay://remote/play-pause": .playPause,
        "media-control-relay://remote/previous": .previous,
        "media-control-relay://remote/next": .next,
        "media-control-relay://remote/seek/forward/10": .seek(10),
        "media-control-relay://remote/seek/forward/30": .seek(30),
        "media-control-relay://remote/seek/backward/10": .seek(-10),
        "media-control-relay://remote/seek/backward/30": .seek(-30),
        "media-control-relay://remote/volume/up": .volume(1),
        "media-control-relay://remote/volume/down": .volume(-1),
    ]

    static func action(for url: URL) -> MediaRemoteAction? {
        guard url.scheme == scheme,
              url.host == host,
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        return canonicalActions[url.absoluteString]
    }
}
