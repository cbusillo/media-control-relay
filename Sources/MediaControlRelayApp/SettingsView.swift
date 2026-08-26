import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: RelayAppModel

    var body: some View {
        TabView {
            Form {
                Section("Media Target") {
                    LabeledContent("Configured Target") {
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
                        discoveryControls
                    } else {
                        Button("Remove Configured Target", role: .destructive) {
                            model.removeConfiguredTarget()
                        }
                        .accessibilityHint("Removes the configured target and resets its counters")
                    }
                }
                Section("Privacy Boundary") {
                    Text("Discovery shows generic media-renderer labels only. Device addresses, identifiers, model names, and control URLs are never displayed or copied to diagnostics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                recoveryControls
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
                    Text("Configuration is stored locally without credentials. A selected media renderer is contacted only on the local network for discovery and volume control.")
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
                        value: model.targetConnectionDiagnosticName
                    )
                    LabeledContent(
                        "Network Path",
                        value: model.networkPathSnapshot.status.rawValue
                    )
                    LabeledContent(
                        "Network Changes",
                        value: model.networkTransitionCount.formatted()
                    )
                    LabeledContent(
                        "Recovery Attempts",
                        value: model.targetRecoveryAttempts.formatted()
                    )
                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                }
                Section {
                    Text("Diagnostics contain only coarse target, activation, command-count, network-state, route-transport, and display-count fields. Local target names, network interface names, and route identifiers are never copied.")
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

    @ViewBuilder
    private var discoveryControls: some View {
        switch model.discovery.state {
        case .idle:
            Button("Find Media Renderers") {
                model.discovery.startScan()
            }
            Text("Searches this network without displaying or storing device addresses.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .scanning:
            ProgressView("Looking for media renderers on this network…")
            Button("Stop") {
                model.discovery.cancelScan()
            }
        case let .results(choices):
            discoveryChoices(choices)
        case .empty:
            Text("No compatible media renderers responded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Search Again") {
                model.discovery.startScan()
            }
        case .failed:
            Text("Couldn’t search this network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Search Again") {
                model.discovery.startScan()
            }
        case let .routeUnavailable(choices):
            Text("Switch your Mac to the audio output you want to control, then choose a target below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            discoveryChoices(choices)
            Button("Search Again") {
                model.discovery.startScan()
            }
        }
    }

    @ViewBuilder
    private var recoveryControls: some View {
        switch model.relayState {
        case .needsLocalNetworkPermission:
            Section("Local Network Recovery") {
                Text(model.statusCopy.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security") {
                    model.openLocalNetworkSettings()
                }
                Button("Check Access Again") {
                    model.retryTargetConnection()
                }
            }
        case .targetAuthenticationRejected:
            Section("Target Recovery") {
                Text(model.statusCopy.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Reaching Target Again") {
                    model.retryTargetConnection()
                }
            }
        case .offline:
            if model.targetConfiguration?.target.kind == .upnpMediaRenderer {
                Section("Target Recovery") {
                    Text(model.statusCopy.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Reaching Target Again") {
                        model.retryTargetConnection()
                    }
                }
            }
        case .unconfigured,
             .unsupported,
             .needsPermission,
             .dormant,
             .checkingTarget,
             .active:
            EmptyView()
        }
    }

    @ViewBuilder
    private func discoveryChoices(_ choices: [MediaTargetDiscoveryChoice]) -> some View {
        ForEach(choices) { choice in
            HStack {
                Text(choice.label)
                Spacer()
                Button("Use This Target") {
                    model.selectDiscoveredTarget(choice)
                }
                .accessibilityLabel("Use \(choice.label)")
                .accessibilityHint("Selects this media renderer and captures the current audio route")
            }
        }
    }
}
