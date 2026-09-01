import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    let model: RelayAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(model.statusCopy.title)
                } icon: {
                    Image(systemName: model.statusCopy.systemImage)
                }
                    .font(.headline)
                Text(model.statusCopy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let accessibleTargetStatus = model.accessibleTargetStatus {
                Text(accessibleTargetStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Confirmed target status")
                    .accessibilityValue(accessibleTargetStatus)
            }

            HStack {
                Button("Volume Down", systemImage: "speaker.minus") {
                    model.handleMenuVolumeAction(.down)
                }
                .accessibilityLabel("Volume Down")
                .accessibilityHint(targetControlAccessibilityHint)
                Button("Mute", systemImage: "speaker.slash") {
                    model.handleMenuVolumeAction(.mute)
                }
                .accessibilityLabel("Mute")
                .accessibilityHint(targetControlAccessibilityHint)
                Button("Volume Up", systemImage: "speaker.plus") {
                    model.handleMenuVolumeAction(.up)
                }
                .accessibilityLabel("Volume Up")
                .accessibilityHint(targetControlAccessibilityHint)
            }
            .labelStyle(.iconOnly)
            .disabled(!model.targetControlsEnabled)

            Divider()

            Button("See Setup Preview…") {
                openWindow(id: "setup")
                NSApp.activate()
            }
            .accessibilityLabel("See Setup Preview")
            .accessibilityHint("Opens the Media Control Relay setup window")

            SettingsLink {
                Text("Open Settings…")
            }
            .accessibilityLabel("Open Settings")

            Divider()

            Button("Quit Media Control Relay") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityLabel("Quit Media Control Relay")
        }
        .frame(width: 280)
    }

    private var targetControlAccessibilityHint: LocalizedStringKey {
        model.targetControlsEnabled
            ? "Controls the configured media target."
            : "Available when the configured media target is active."
    }
}
