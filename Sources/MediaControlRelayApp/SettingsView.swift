import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: RelayAppModel

    var body: some View {
        TabView {
            Form {
                Section("Media Target") {
                    LabeledContent("Preview Target") {
                        Text(model.configuredDeviceName)
                    }
                    LabeledContent("Status") {
                        Text(model.statusCopy.title)
                    }
                    LabeledContent(
                        "Audio Transport",
                        value: model.routeSnapshot.audioOutput?.transportKind.rawValue ?? "none"
                    )
                    LabeledContent(
                        "Active Displays",
                        value: model.routeSnapshot.displays.count.formatted()
                    )
                    LabeledContent("Selected Route") {
                        Text(model.selectedPreviewRouteDescription)
                    }
                    LabeledContent(
                        "Activation",
                        value: model.targetConfiguration == nil
                            ? "Unconfigured"
                            : model.activationMatches ? "Match" : "No match"
                    )
                    LabeledContent("Commands Recorded", value: model.commandsRecorded.formatted())
                    LabeledContent("Actions Not Recorded", value: model.commandsSuppressed.formatted())

                    if model.targetConfiguration == nil {
                        Button("Create Preview Target") {
                            model.createPreviewTarget()
                        }
                        .disabled(!model.canCreatePreviewTarget)
                        .accessibilityHint("Creates a local in-process recording target")
                    } else {
                        Button("Remove Preview Target", role: .destructive) {
                            model.removePreviewTarget()
                        }
                        .accessibilityHint("Removes the local target and resets its counters")
                    }
                }
                Section("Preview Boundary") {
                    Text(model.previewTargetExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Media Target", systemImage: "record.circle")
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
                    Text("Launch at login is not part of this preview.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("The preview target is stored locally in UserDefaults. It has no credentials and does not use the network.")
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
                    LabeledContent("Target Kind", value: model.targetConfiguration?.target.kind.rawValue ?? "unconfigured")
                    LabeledContent(
                        "Activation",
                        value: model.targetConfiguration == nil
                            ? "unconfigured"
                            : model.activationMatches ? "match" : "no-match"
                    )
                    LabeledContent("Commands Recorded", value: model.commandsRecorded.formatted())
                    LabeledContent("Actions Not Recorded", value: model.commandsSuppressed.formatted())
                    LabeledContent(
                        "Target Connection",
                        value: model.targetConfiguration == nil ? "not-available" : "preview-sink"
                    )
                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                }
                Section {
                    Text("Diagnostics contain only coarse target, activation, command-count, route-transport, and display-count fields. Local target names and route identifiers are never copied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Diagnostics", systemImage: "stethoscope")
            }
        }
        .frame(width: 600, height: 500)
    }
}
