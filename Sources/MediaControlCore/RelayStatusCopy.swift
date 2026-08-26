import Foundation

public struct RelayStatusCopy: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }
}

public enum RelayStatusCopyCatalog {
    public static func copy(
        for state: RelayState,
        targetKind: RelayTargetKind?
    ) -> RelayStatusCopy {
        if targetKind == .preview {
            switch state {
            case .unconfigured:
                break
            case .unsupported:
                return RelayStatusCopy(
                    title: "Preview target is unsupported",
                    detail: "Remove this target and create a new in-process preview target.",
                    systemImage: "exclamationmark.triangle"
                )
            case .needsPermission:
                return RelayStatusCopy(
                    title: "Allow volume key access",
                    detail: "Allow Media Control Relay to detect your Mac’s volume and mute keys.",
                    systemImage: "hand.raised.fill"
                )
            case .needsLocalNetworkPermission:
                return RelayStatusCopy(
                    title: "Preview target cannot use the network",
                    detail: "The in-process preview target does not require local-network access.",
                    systemImage: "exclamationmark.triangle"
                )
            case .targetAuthenticationRejected:
                return RelayStatusCopy(
                    title: "Preview target rejected control",
                    detail: "The in-process preview target does not authenticate with a media device.",
                    systemImage: "exclamationmark.triangle"
                )
            case .dormant:
                return RelayStatusCopy(
                    title: "Preview target is dormant",
                    detail: "The current route does not match the selected preview route, so your Mac continues handling volume normally.",
                    systemImage: "speaker.wave.2"
                )
            case .checkingTarget:
                return RelayStatusCopy(
                    title: "Checking preview target",
                    detail: "Checking the current route before recording preview commands.",
                    systemImage: "questionmark.circle"
                )
            case .offline:
                return RelayStatusCopy(
                    title: "Preview target is unavailable",
                    detail: "The preview sink is not reachable, and your Mac continues handling volume normally.",
                    systemImage: "exclamationmark.triangle"
                )
            case .active:
                return RelayStatusCopy(
                    title: "Recording to preview target",
                    detail: "Recording and relaying volume actions to an in-process preview target. No TV or media device is connected or controlled, and your Mac continues handling volume normally.",
                    systemImage: "record.circle"
                )
            }
        }

        switch state {
        case .unconfigured:
            return RelayStatusCopy(
                title: "No media target selected",
                detail: "Open Settings to create a preview target or find a compatible media renderer.",
                systemImage: "record.circle"
            )
        case .unsupported:
            return RelayStatusCopy(
                title: "This media target isn’t supported",
                detail: "Choose another media target or check the compatibility list.",
                systemImage: "tv.badge.xmark"
            )
        case .needsPermission:
            return RelayStatusCopy(
                title: "Allow volume key access",
                detail: "Allow Media Control Relay to detect your Mac’s volume and mute keys.",
                systemImage: "hand.raised.fill"
            )
        case .needsLocalNetworkPermission:
            return RelayStatusCopy(
                title: "Allow local network access",
                detail: "Enable Media Control Relay in Privacy & Security > Local Network, then check access again.",
                systemImage: "network.badge.shield.half.filled"
            )
        case .targetAuthenticationRejected:
            return RelayStatusCopy(
                title: "Media target rejected control",
                detail: "The selected target rejected pairing-free volume control. Check its settings or choose another target.",
                systemImage: "lock.trianglebadge.exclamationmark"
            )
        case .dormant:
            return RelayStatusCopy(
                title: "Using Mac volume",
                detail: "The selected media target is not the current audio and display route, so your Mac handles the volume keys.",
                systemImage: "speaker.wave.2"
            )
        case .checkingTarget:
            return RelayStatusCopy(
                title: "Checking media target",
                detail: "Checking the selected media target before routing volume commands.",
                systemImage: "questionmark.circle"
            )
        case .offline:
            return RelayStatusCopy(
                title: "Can’t reach your media target",
                detail: "Make sure the media target is on and connected to the same network as your Mac.",
                systemImage: "wifi.exclamationmark"
            )
        case .active:
            return RelayStatusCopy(
                title: "Controlling media volume",
                detail: "Your Mac’s volume and mute keys are controlling the selected media device.",
                systemImage: "speaker.wave.2.fill"
            )
        }
    }
}
