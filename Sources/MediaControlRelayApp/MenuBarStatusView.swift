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

            Divider()

            Button("See Setup Preview…") {
                openWindow(id: "setup")
                NSApp.activate()
            }

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit Media Control Relay") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
    }
}
