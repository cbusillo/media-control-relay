import AppKit
import Observation
import VolumeBridgeCore

@MainActor
@Observable
final class BridgeAppModel {
    var bridgeState: BridgeState = .unconfigured
    var launchAtLogin = false

    let productStatus: LocalizedStringResource = "Preview build"
    let configuredDeviceName: LocalizedStringResource = "No TV selected"

    var buildDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var diagnosticsSummary: String {
        let fields = [
            "app_version": buildDescription,
            "bridge_state": bridgeState.diagnosticName,
            "macos_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "product_status": "preview",
            "setup_complete": "no",
            "tv_connection": "not-available",
        ]
        let allowedFieldNames: Set<String> = [
            "app_version",
            "bridge_state",
            "macos_version",
            "product_status",
            "setup_complete",
            "tv_connection",
        ]
        return DiagnosticsRedaction.redact(
            fields: DiagnosticsRedaction.allowlisted(
                fields: fields,
                allowedFieldNames: allowedFieldNames
            )
        )
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "\n")
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsSummary, forType: .string)
    }
}

extension BridgeState {
    var title: LocalizedStringResource {
        switch self {
        case .unconfigured: "TV setup is coming soon"
        case .unsupported: "This TV isn’t supported"
        case .needsPermission: "Allow volume key access"
        case .dormant: "Using Mac volume"
        case .offline: "Can’t reach your TV"
        case .active: "Controlling TV volume"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .unconfigured:
            "This preview shows the setup flow but can’t connect to a TV yet."
        case .unsupported:
            "Choose another TV or check the compatibility list."
        case .needsPermission:
            "Allow TV Volume Bridge to respond to your Mac’s volume and mute keys."
        case .dormant:
            "Your TV isn’t the current sound output, so your Mac handles the volume keys."
        case .offline:
            "Make sure the TV is on and connected to the same network as your Mac."
        case .active:
            "Your Mac’s volume and mute keys are controlling the TV."
        }
    }

    var localizedTitle: String {
        String(localized: title)
    }

    var systemImage: String {
        switch self {
        case .active: "speaker.wave.2.fill"
        case .dormant: "speaker.wave.2"
        case .offline: "wifi.exclamationmark"
        case .needsPermission: "hand.raised.fill"
        case .unsupported: "tv.badge.xmark"
        case .unconfigured: "tv.badge.wifi"
        }
    }

    var diagnosticName: String {
        switch self {
        case .unconfigured: "unconfigured"
        case .unsupported: "unsupported"
        case .needsPermission: "needs-permission"
        case .dormant: "dormant"
        case .offline: "offline"
        case .active: "active"
        }
    }
}
