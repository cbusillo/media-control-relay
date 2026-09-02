import Foundation
import SwiftUI

@main
struct RelayApp: App {
    @AppStorage("hasShownWelcome") private var hasShownWelcome = false
    @State private var model: RelayAppModel
    @NSApplicationDelegateAdaptor(RelayAppDelegate.self)
    private var appDelegate

    init() {
        _model = State(initialValue: Self.makeModel())
    }

    var body: some Scene {
        Window("Media Control Relay Setup", id: "setup") {
            SetupView(model: model)
                .onAppear {
                    hasShownWelcome = true
                    appDelegate.attach(model: model)
                }
        }
        .defaultSize(width: 560, height: 520)
        .defaultLaunchBehavior(hasShownWelcome ? .suppressed : .presented)
        .handlesExternalEvents(matching: [])
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarStatusView(model: model)
                .onAppear {
                    appDelegate.attach(model: model)
                }
        } label: {
            Image(systemName: model.statusCopy.systemImage)
                .accessibilityLabel(
                    model.menuBarAccessibilityLabel
                )
                .onAppear {
                    appDelegate.attach(model: model)
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .onAppear {
                    appDelegate.attach(model: model)
                }
        }
    }

    @MainActor
    private static func makeModel() -> RelayAppModel {
#if DEBUG
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            return RelayAppModel(
                targetOverlayPresenter: TargetOverlayController(),
                remoteControl: RemoteControlRuntimeFactory.make()
            )
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
            accessibilityAccess: .denied,
            launchAtLoginClient: LaunchAtLoginClient(
                status: { .notRegistered },
                register: {},
                unregister: {},
                openSystemSettingsLoginItems: {}
            )
        )
#else
        RelayAppModel(
            targetOverlayPresenter: TargetOverlayController(),
            remoteControl: RemoteControlRuntimeFactory.make()
        )
#endif
    }
}
