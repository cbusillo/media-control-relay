import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: RelayAppModel

    var body: some View {
        TabView {
            Form {
                Section {
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
                        .accessibilityLabel("Create Preview Target")
                        .accessibilityHint("Creates a local in-process recording target")
                        discoveryControls
                    } else {
                        Button("Remove Configured Target", role: .destructive) {
                            model.removeConfiguredTarget()
                        }
                        .accessibilityLabel("Remove Configured Target")
                        .accessibilityHint("Removes the configured target and resets its counters")
                    }
                } header: {
                    SettingsSectionHeader("Media Target")
                }
                Section {
                    Text("Discovery shows generic media-renderer labels only. Device addresses, identifiers, model names, and control URLs are never displayed or copied to diagnostics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SettingsSectionHeader("Privacy Boundary")
                }
                recoveryControls
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Media Target", systemImage: "record.circle")
            }

            if let remoteControl = model.remoteControl {
                RemoteControlSettingsView(model: remoteControl)
                    .tabItem {
                        Label("Apple TV", systemImage: "appletv")
                    }
            }

            Form {
                Section {
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
                            .accessibilityLabel("Allow Volume Key Access")
                        case .requested:
                            Button("Quit to Apply Volume Key Access") {
                                model.quitApplication()
                            }
                            .accessibilityLabel("Quit to Apply Volume Key Access")
                            .accessibilityHint("Quits Media Control Relay so the permission can take effect")
                            Button("Open Input Monitoring Settings") {
                                model.openInputMonitoringSettings()
                            }
                            .accessibilityLabel("Open Input Monitoring Settings")
                        case .denied:
                            Button("Open Input Monitoring Settings") {
                                model.openInputMonitoringSettings()
                            }
                            .accessibilityLabel("Open Input Monitoring Settings")
                            Button("Quit After Changing Volume Key Access") {
                                model.quitApplication()
                            }
                            .accessibilityLabel("Quit After Changing Volume Key Access")
                        case .granted:
                            Button("Quit and Reopen Media Control Relay") {
                                model.quitApplication()
                            }
                            .accessibilityLabel("Quit and Reopen Media Control Relay")
                        }
                    }
                } header: {
                    SettingsSectionHeader("Volume Key Access")
                }

                Section {
                    LabeledContent("Status") {
                        Label {
                            Text(model.accessibilityTitle)
                        } icon: {
                            Image(systemName: model.accessibilitySystemImage)
                        }
                    }
                    Text(model.accessibilityDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    switch model.accessibilityAuthorization {
                    case .notDetermined:
                        Button("Allow Native HUD Replacement") {
                            model.requestAccessibility()
                        }
                        .accessibilityLabel("Allow Native HUD Replacement")
                    case .requested:
                        Button("Quit to Apply Native HUD Access") {
                            model.quitApplication()
                        }
                        .accessibilityLabel("Quit to Apply Native HUD Access")
                        .accessibilityHint("Quits Media Control Relay so the permission can take effect")
                        Button("Open Accessibility Settings") {
                            model.openAccessibilitySettings()
                        }
                        .accessibilityLabel("Open Accessibility Settings")
                    case .denied:
                        Button("Open Accessibility Settings") {
                            model.openAccessibilitySettings()
                        }
                        .accessibilityLabel("Open Accessibility Settings")
                        Button("Quit After Changing Accessibility Access") {
                            model.quitApplication()
                        }
                        .accessibilityLabel("Quit After Changing Accessibility Access")
                    case .granted:
                        if model.volumeKeySuppressionMode != .conditional {
                            Button("Quit and Reopen Media Control Relay") {
                                model.quitApplication()
                            }
                            .accessibilityLabel("Quit and Reopen Media Control Relay")
                        }
                    }
                } header: {
                    SettingsSectionHeader("Native Volume HUD")
                }

                Section {
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .disabled(!model.launchAtLoginState.toggleAvailable)
                    LabeledContent("Status") {
                        Label {
                            Text(model.launchAtLoginState.title)
                        } icon: {
                            Image(systemName: model.launchAtLoginState.systemImage)
                        }
                    }
                    Text(model.launchAtLoginState.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let operationFailure = model.launchAtLoginOperationFailure {
                        Text(operationFailure.failureDetail)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if model.launchAtLoginState.recoveryActionAvailable {
                        Button("Open Login Items Settings") {
                            model.openLaunchAtLoginSettings()
                        }
                        .accessibilityLabel("Open Login Items Settings")
                        .accessibilityHint("Opens System Settings so launch at login can be approved")
                    }
                } header: {
                    SettingsSectionHeader("General")
                }
                Section {
                    Text("Configuration is stored locally without credentials. A selected media renderer is contacted only on the local network for discovery and volume control.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader("Privacy")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section {
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
                    .accessibilityLabel("Copy Diagnostics")
                    .accessibilityHint("Copies privacy-safe diagnostics to the clipboard")
                } header: {
                    SettingsSectionHeader("Diagnostics")
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
            .accessibilityLabel("Find Media Renderers")
            Text("Searches this network without displaying or storing device addresses.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .scanning:
            ProgressView("Looking for media renderers on this network…")
            Button("Stop") {
                model.discovery.cancelScan()
            }
            .accessibilityLabel("Stop Media Renderer Search")
        case let .results(choices):
            discoveryChoices(choices)
        case .empty:
            Text("No compatible media renderers responded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Search for Media Renderers Again") {
                model.discovery.startScan()
            }
            .accessibilityLabel("Search for Media Renderers Again")
        case .localNetworkDenied:
            if model.networkPathSnapshot.status == .available ||
                model.networkPathSnapshot.status == .localNetworkDenied {
                Text("Local-network access is unavailable. Enable Media Control Relay in Privacy & Security, then check access again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Local Network Settings") {
                    model.openLocalNetworkSettings()
                }
                .accessibilityLabel("Open Local Network Settings")
                Button("Check Local Network Access Again") {
                    model.discovery.startScan()
                }
                .accessibilityLabel("Check Local Network Access Again")
            } else {
                Text("Couldn’t search this network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Search for Media Renderers Again") {
                    model.discovery.startScan()
                }
                .accessibilityLabel("Search for Media Renderers Again")
            }
        case .failed:
            Text("Couldn’t search this network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Search for Media Renderers Again") {
                model.discovery.startScan()
            }
            .accessibilityLabel("Search for Media Renderers Again")
        case let .routeUnavailable(choices):
            Text("Switch your Mac to the audio output you want to control, then choose a target below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            discoveryChoices(choices)
            Button("Search for Media Renderers Again") {
                model.discovery.startScan()
            }
            .accessibilityLabel("Search for Media Renderers Again")
        }
    }

    @ViewBuilder
    private var recoveryControls: some View {
        switch model.relayState {
        case .needsLocalNetworkPermission:
            Section {
                Text(model.statusCopy.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Local Network Settings") {
                    model.openLocalNetworkSettings()
                }
                .accessibilityLabel("Open Local Network Settings")
                Button("Check Local Network Access Again") {
                    model.retryTargetConnection()
                }
                .accessibilityLabel("Check Local Network Access Again")
            } header: {
                SettingsSectionHeader("Local Network Recovery")
            }
        case .targetAuthenticationRejected:
            Section {
                Text(model.statusCopy.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Reaching Target Again") {
                    model.retryTargetConnection()
                }
                .accessibilityLabel("Try Reaching Target Again")
            } header: {
                SettingsSectionHeader("Target Recovery")
            }
        case .offline:
            if model.targetConfiguration?.target.kind == .upnpMediaRenderer {
                Section {
                    Text(model.statusCopy.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Reaching Target Again") {
                        model.retryTargetConnection()
                    }
                    .accessibilityLabel("Try Reaching Target Again")
                } header: {
                    SettingsSectionHeader("Target Recovery")
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
                .accessibilityLabel("Use This Target, \(choice.label)")
                .accessibilityHint("Selects this media renderer and captures the current audio route")
            }
        }
    }
}

struct SettingsSectionHeader: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }
}
