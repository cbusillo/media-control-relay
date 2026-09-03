import AppKit
import MediaControlCore
import SwiftUI

struct RemoteControlSettingsView: View {
    @Bindable var model: RemoteControlModel
    @State private var showsForgetConfirmation = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        Form {
            Section {
                statusContent
            } header: {
                SettingsSectionHeader("Apple TV")
            }

            if case let .ready(capabilities) = model.state {
                capabilityContent(capabilities)
            }

            Section {
                Text("Device names are used only while you choose and pair. Hosts, identifiers, PINs, credentials, and helper paths are never shown or copied to diagnostics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SettingsSectionHeader("Privacy Boundary")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Forget this Apple TV?",
            isPresented: $showsForgetConfirmation
        ) {
            Button("Forget Apple TV", role: .destructive) {
                model.forgetCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll need the on-screen PIN to connect again.")
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.state {
        case .helperNotInstalled:
            status(
                title: "Apple TV controls aren’t installed",
                detail: "This build can use the optional local Apple TV helper, but it isn’t installed on this Mac.",
                systemImage: "shippingbox"
            )
            Button("Copy Setup Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "scripts/apple-companion-helper.sh install",
                    forType: .string
                )
            }
            Button("Check Again") { model.refreshAvailability() }
        case .helperDamaged:
            status(
                title: "Apple TV helper needs attention",
                detail: "The local helper failed verification and won’t be used.",
                systemImage: "exclamationmark.triangle"
            )
            Button("Check Again") { model.refreshAvailability() }
        case .unconfigured:
            status(
                title: "No Apple TV connected",
                detail: "Connect an Apple TV to use navigation, transport, seek, and volume controls.",
                systemImage: "appletv"
            )
            Button("Find Apple TVs") { model.discover() }
                .accessibilityHint("Searches the local network for Apple TVs")
        case .discovering:
            ProgressView("Looking for Apple TVs on this network…")
            Button("Stop") { model.cancelDiscovery() }
                .keyboardShortcut(.cancelAction)
        case .empty:
            status(
                title: "No Apple TVs responded",
                detail: "Make sure the Apple TV is awake and on the same network, then search again.",
                systemImage: "wifi.exclamationmark"
            )
            Button("Search Again") { model.discover() }
        case let .choosing(choices):
            status(
                title: "Choose an Apple TV",
                detail: "Only the temporary display name is shown.",
                systemImage: "appletv"
            )
            ForEach(choices) { choice in
                HStack {
                    Text(choice.name)
                    Spacer()
                    Button("Connect") { model.select(choice) }
                        .accessibilityLabel("Connect to \(choice.name)")
                }
            }
            Button("Search Again") { model.discover() }
        case let .pairing(choice, failedAttempts):
            status(
                title: "Enter the PIN shown on \(choice.name)",
                detail: failedAttempts > 0
                    ? "That PIN didn’t work. Try again."
                    : "The PIN is used only for this pairing request.",
                systemImage: "number.square"
            )
            TextField("PIN", text: $model.pairingPIN)
                .textFieldStyle(.roundedBorder)
                .focused($pinFocused)
                .onAppear { pinFocused = true }
                .onChange(of: model.pairingPIN) { _, value in
                    model.pairingPIN = String(value.filter { $0.isNumber }.prefix(4))
                }
                .onSubmit { model.finishPairing() }
                .accessibilityHint("Enter the four-digit PIN displayed by the Apple TV")
            Button("Pair") { model.finishPairing() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.pairingPIN.count != 4)
            Button("Cancel") { model.cancelDiscovery() }
                .keyboardShortcut(.cancelAction)
        case let .connecting(reconnecting):
            ProgressView(reconnecting ? "Reconnecting to Apple TV…" : "Connecting to Apple TV…")
            Button("Cancel") { model.disconnect() }
                .keyboardShortcut(.cancelAction)
        case .ready:
            status(
                title: "Apple TV is ready",
                detail: "Remote actions are enabled only when the Apple TV reports the matching capability.",
                systemImage: "checkmark.circle.fill"
            )
            Button("Disconnect") { model.disconnect() }
            Button("Forget This Apple TV", role: .destructive) {
                showsForgetConfirmation = true
            }
        case .unsupported:
            status(
                title: "This Apple TV isn’t supported",
                detail: "It didn’t offer the remote controls Media Control Relay needs.",
                systemImage: "nosign"
            )
            Button("Forget This Apple TV", role: .destructive) {
                showsForgetConfirmation = true
            }
        case let .offline(manual):
            status(
                title: manual ? "Apple TV is disconnected" : "Apple TV is offline",
                detail: manual
                    ? "The saved connection is still available."
                    : "Turn it on and keep it on the same network, then try again.",
                systemImage: "appletv.fill"
            )
            Button("Try Reaching Apple TV Again") { model.retry() }
            Button("Forget This Apple TV", role: .destructive) {
                showsForgetConfirmation = true
            }
        case let .credentialFailure(operation):
            status(
                title: credentialFailureTitle(operation),
                detail: "Check that your login Keychain is available, then try again.",
                systemImage: "key.slash"
            )
            Button("Try Again") {
                switch operation {
                case .read:
                    model.startIfNeeded()
                case .write:
                    model.retryCredentialSave()
                case .remove:
                    model.forgetCredentials()
                }
            }
            if operation == .write {
                Button("Start Over") {
                    model.cancelDiscovery()
                }
            }
        }

        if let operationMessage = model.operationMessage {
            Text(operationMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func capabilityContent(_ capabilities: Set<MediaRemoteCapability>) -> some View {
        Section {
            ForEach(capabilities.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                Label(capabilityTitle(capability), systemImage: capabilitySystemImage(capability))
            }
            Text("Mute isn’t available for Apple TV. Use volume down.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Play/Pause sends a toggle. Media Control Relay doesn’t know whether your Apple TV is playing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SettingsSectionHeader("Available Controls")
        }
    }

    private func status(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func capabilityTitle(_ capability: MediaRemoteCapability) -> LocalizedStringKey {
        switch capability {
        case .navigation: "Navigation"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .playPause: "Play/Pause Toggle"
        case .previous: "Previous"
        case .next: "Next"
        case .relativeSeek: "Relative Seek"
        case .relativeVolume: "Relative Volume"
        }
    }

    private func credentialFailureTitle(
        _ operation: RemoteControlCredentialOperation
    ) -> LocalizedStringKey {
        switch operation {
        case .read:
            "Couldn’t read the saved connection"
        case .write:
            "Couldn’t save the Apple TV connection"
        case .remove:
            "Couldn’t remove the saved connection"
        }
    }

    private func capabilitySystemImage(_ capability: MediaRemoteCapability) -> String {
        switch capability {
        case .navigation: "arrow.up.and.down.and.arrow.left.and.right"
        case .select: "button.programmable"
        case .back: "chevron.backward"
        case .home: "house"
        case .playPause: "playpause"
        case .previous: "backward.end"
        case .next: "forward.end"
        case .relativeSeek: "gobackward.10"
        case .relativeVolume: "speaker.wave.2"
        }
    }
}
