import Foundation
import SwiftUI

@main
struct RelayApp: App {
#if DEBUG
    // Keep hosted-test settings with the disposable build products, not user preferences.
    static let testHostPreferencesDomain = Bundle.main.bundleURL
        .deletingLastPathComponent()
        .appendingPathComponent("MCRTestHostPreferences").path

    static let testHostPreferences: UserDefaults = {
        let defaults = UserDefaults(suiteName: testHostPreferencesDomain)!
        defaults.removePersistentDomain(forName: testHostPreferencesDomain)
        return defaults
    }()
#endif

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
            Image(nsImage: RelayMenuBarIcon.image)
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
                targetOverlayPresenter: TargetOverlayController()
            )
        }

        return RelayAppModel(
            routeObserver: InactiveRouteObserver(),
            networkPathObserver: InactiveNetworkPathObserver(),
            configurationStore: RelayConfigurationStore(defaults: testHostPreferences),
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
#elseif APP_STORE
        // The Mac App Store build never requests Accessibility, so volume keys
        // stay on the listen-only Input Monitoring tap. See
        // docs/app-store-distribution.md.
        RelayAppModel(
            accessibilityAccess: .denied,
            targetOverlayPresenter: TargetOverlayController()
        )
#else
        RelayAppModel(
            targetOverlayPresenter: TargetOverlayController()
        )
#endif
    }
}
