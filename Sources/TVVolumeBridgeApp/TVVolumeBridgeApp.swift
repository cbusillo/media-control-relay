import SwiftUI

@main
struct TVVolumeBridgeApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome = false
    @State private var model = BridgeAppModel()

    var body: some Scene {
        Window("TV Volume Bridge Setup", id: "setup") {
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
            Image(systemName: model.bridgeState.systemImage)
                .accessibilityLabel(
                    "TV Volume Bridge, \(model.bridgeState.localizedTitle)"
                )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
