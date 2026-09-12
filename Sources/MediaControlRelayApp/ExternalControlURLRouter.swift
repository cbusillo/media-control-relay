import Foundation
import MediaControlCore

enum ExternalControlURLRouter {
    enum Route: Equatable {
        case activeOutputVolume(VolumeAction)
        case rejected
    }

    static func route(for url: URL) -> Route {
        guard let action = ExternalVolumeActionURLParser.action(for: url) else {
            return .rejected
        }
        return .activeOutputVolume(action)
    }
}
