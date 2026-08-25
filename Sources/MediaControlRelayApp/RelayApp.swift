import SwiftUI

@main
struct RelayApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome = false
    @State private var model = RelayAppModel()

    var body: some Scene {
        Window("Media Control Relay Setup", id: "setup") {
            SetupView(model: model)
                .onAppear {
                    hasShownWelcome = true
                }
        }
        .defaultSize(width: 560, height: 520)
        .defaultLaunchBehavior(hasShownWelcome ? .suppressed : .presented)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarStatusView(model: model)
        } label: {
            Image(systemName: model.relayState.systemImage)
                .accessibilityLabel(
                    "Media Control Relay, \(model.relayState.localizedTitle)"
                )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
