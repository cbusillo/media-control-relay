import Foundation
import MediaControlCore

public struct UPnPMediaTargetDescriptor: Equatable, Sendable {
    public let identity: MediaTargetIdentity
    public let renderingControlURL: URL

    public init(
        identity: MediaTargetIdentity,
        renderingControlURL: URL
    ) {
        self.identity = identity
        self.renderingControlURL = renderingControlURL
    }
}

