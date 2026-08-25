import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: RelayAppModel

    var body: some View {
        TabView {
            Form {
                Section("Media Target") {
                    LabeledContent("Device") {
                        Text(model.configuredDeviceName)
                    }
                    LabeledContent("Status") {
                        Text(model.relayState.title)
                    }
                }
                Section {
                    Text("Media target setup isn’t available in this preview.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Media Target", systemImage: "tv")
            }

            Form {
                Section("Volume Key Access") {
                    LabeledContent("Status") {
                        Label {
                            Text(model.inputMonitoringTitle)
                        } icon: {
                            Image(systemName: model.inputMonitoringSystemImage)
                        }
                    }
                    Text(model.inputMonitoringDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.inputMonitoringAuthorization == .granted,
                       !model.inputMonitoringUnavailable {
                        LabeledContent(
                            "Detected Presses",
                            value: model.observedVolumeKeyPressCount.formatted()
                        )
                        if let lastAction = model.lastObservedVolumeActionTitle {
                            LabeledContent("Last Detected") {
                                Text(lastAction)
                            }
                        }
                    } else {
                        switch model.inputMonitoringAuthorization {
                        case .notDetermined:
                            Button("Allow Volume Key Access") {
                                model.requestInputMonitoring()
                            }
                        case .requested:
                            Button("Quit to Apply Access") {
                                model.quitApplication()
                            }
                            Button("Open Privacy & Security") {
                                model.openInputMonitoringSettings()
                            }
                        case .denied:
                            Button("Open Privacy & Security") {
                                model.openInputMonitoringSettings()
                            }
                            Button("Quit After Changing Access") {
                                model.quitApplication()
                            }
                        case .granted:
                            Button("Quit and Reopen Media Control Relay") {
                                model.quitApplication()
                            }
                        }
                    }
                }

                Section("General") {
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                        .disabled(true)
                    Text("Available after you finish setting up a media target.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Media Control Relay works on your local network and does not require an account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Diagnostics") {
                    LabeledContent("Build", value: model.buildDescription)
                    LabeledContent(
                        "Route Observation",
                        value: model.routeObservationState.rawValue
                    )
                    LabeledContent(
                        "Audio Transport",
                        value: model.routeSnapshot.audioOutput?.transportKind.rawValue ?? "none"
                    )
                    LabeledContent(
                        "Active Displays",
                        value: model.routeSnapshot.displays.count.formatted()
                    )
                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                }
                Section {
                    Text("Copied diagnostics leave out your media target address and private connection details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Diagnostics", systemImage: "stethoscope")
            }
        }
        .frame(width: 560, height: 380)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshInputMonitoring()
        }
    }
}
