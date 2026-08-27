import Foundation
import MediaControlCore

public struct UPnPMediaTargetDeviceDescription: Equatable, Sendable {
    public let identity: MediaTargetIdentity
    public let renderingControlURL: URL
    public let renderingControlSCPDURL: URL

    public init(
        identity: MediaTargetIdentity,
        renderingControlURL: URL,
        renderingControlSCPDURL: URL
    ) {
        self.identity = identity
        self.renderingControlURL = renderingControlURL
        self.renderingControlSCPDURL = renderingControlSCPDURL
    }
}

public struct UPnPMediaTargetDescriptor: Equatable, Sendable {
    public let identity: MediaTargetIdentity
    public let renderingControlURL: URL
    public let volumeCapability: UPnPMediaTargetVolumeCapability

    public init(
        identity: MediaTargetIdentity,
        renderingControlURL: URL,
        volumeCapability: UPnPMediaTargetVolumeCapability
    ) {
        self.identity = identity
        self.renderingControlURL = renderingControlURL
        self.volumeCapability = volumeCapability
    }
}
