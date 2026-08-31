import Foundation
import SwiftUI

@main
struct RelayApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome = false
    @State private var model: RelayAppModel

    init() {
        _model = State(initialValue: Self.makeModel())
    }

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
            Image(systemName: model.statusCopy.systemImage)
                .accessibilityLabel(
                    "Media Control Relay, \(model.statusCopy.title)"
                )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    @MainActor
    private static func makeModel() -> RelayAppModel {
#if DEBUG
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            return RelayAppModel(targetOverlayPresenter: TargetOverlayController())
        }

        let suiteName = "com.shinycomputers.media-control-relay.test-host"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RelayAppModel(
            routeObserver: InactiveRouteObserver(),
            networkPathObserver: InactiveNetworkPathObserver(),
            configurationStore: RelayConfigurationStore(defaults: defaults),
            volumeKeyMonitor: InactiveVolumeKeyMonitor(),
            inputMonitoringAccess: .denied,
            accessibilityAccess: .denied
        )
#else
        RelayAppModel(targetOverlayPresenter: TargetOverlayController())
#endif
    }
}
