import AppKit
import MediaControlCore
import SwiftUI

struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    let model: RelayAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media Control Relay")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(model.statusCopy.title)
                } icon: {
                    Image(systemName: model.statusCopy.systemImage)
                }
                    .font(.subheadline.weight(.medium))
                if model.relayState != .active || model.targetConfiguration?.target.kind == .preview {
                    Text(model.statusCopy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if let accessibleTargetStatus = model.accessibleTargetStatus {
                Text(accessibleTargetStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Confirmed target status")
                    .accessibilityValue(accessibleTargetStatus)
            }

            HStack(spacing: 8) {
                volumeButton(
                    systemImage: "speaker.minus",
                    accessibilityLabel: "Volume Down",
                    action: .down
                )
                volumeButton(
                    systemImage: "speaker.slash",
                    accessibilityLabel: "Mute",
                    action: .mute
                )
                volumeButton(
                    systemImage: "speaker.plus",
                    accessibilityLabel: "Volume Up",
                    action: .up
                )
            }
            .disabled(!model.targetControlsEnabled)

            if shouldShowSetup {
                Button("Set Up…") {
                    openSetup()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Set Up")
                .accessibilityHint("Opens the Media Control Relay setup window")
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                .accessibilityLabel("Settings")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .accessibilityLabel("Quit Media Control Relay")
            }
        }
        .padding(16)
        .frame(width: 312)
    }

    private var shouldShowSetup: Bool {
        guard model.targetConfiguration != nil else {
            return true
        }
        switch model.relayState {
        case .needsPermission, .needsLocalNetworkPermission:
            return true
        case .unconfigured, .unsupported, .targetAuthenticationRejected,
             .dormant, .checkingTarget, .offline, .active:
            return false
        }
    }

    private func openSetup() {
        openWindow(id: "setup")
        NSApp.activate()
    }

    private func volumeButton(
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        action: VolumeAction
    ) -> some View {
        Button {
            model.handleMenuVolumeAction(action)
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(targetControlAccessibilityHint)
        .help(accessibilityLabel)
    }

    private var targetControlAccessibilityHint: LocalizedStringKey {
        model.targetControlsEnabled
            ? "Controls the configured media target."
            : "Available when the configured media target is active."
    }
}
