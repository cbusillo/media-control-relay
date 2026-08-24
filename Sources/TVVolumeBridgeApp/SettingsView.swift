import SwiftUI

struct SettingsView: View {
    @Bindable var model: BridgeAppModel

    var body: some View {
        TabView {
            Form {
                Section("TV") {
                    LabeledContent("Device") {
                        Text(model.configuredDeviceName)
                    }
                    LabeledContent("Status") {
                        Text(model.bridgeState.title)
                    }
                }
                Section {
                    Text("TV setup isn’t available in this preview.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("TV", systemImage: "tv")
            }

            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                        .disabled(true)
                    Text("Available after you finish setting up a TV.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("TV Volume Bridge works on your local network and does not require an account.")
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
                    Button("Copy Diagnostics") {
                        model.copyDiagnostics()
                    }
                }
                Section {
                    Text("Copied diagnostics leave out your TV address and private connection details.")
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
    }
}
