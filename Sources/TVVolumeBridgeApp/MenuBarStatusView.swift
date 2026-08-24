import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    let model: BridgeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(model.bridgeState.title)
                } icon: {
                    Image(systemName: model.bridgeState.systemImage)
                }
                    .font(.headline)
                Text(model.bridgeState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Divider()

            Button("See Setup Preview…") {
                openWindow(id: "setup")
                NSApp.activate()
            }

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit TV Volume Bridge") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
    }
}
