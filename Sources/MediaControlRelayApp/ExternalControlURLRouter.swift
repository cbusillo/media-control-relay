import Foundation
import MediaControlCore

enum ExternalControlURLRouter {
    enum Route: Equatable {
        case activeOutputVolume(VolumeAction)
        case remote(MediaRemoteAction)
        case rejected
    }

    private static let controlHost = "control"
    private static let remoteHost = "remote"

    static func route(for url: URL) -> Route {
        guard let host = url.host else {
            return .rejected
        }

        switch host {
        case controlHost:
            guard let action = ExternalVolumeActionURLParser.action(for: url) else {
                return .rejected
            }
            return .activeOutputVolume(action)

        case remoteHost:
            guard let action = ExternalRemoteActionURLParser.action(for: url) else {
                return .rejected
            }
            return .remote(action)

        default:
            return .rejected
        }
    }
}
