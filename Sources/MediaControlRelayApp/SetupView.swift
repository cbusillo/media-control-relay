import AppKit
import SwiftUI

struct SetupView: View {
    @Environment(\.openSettings) private var openSettings
    let model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Media Control Relay")
                            .font(.largeTitle.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Route Mac volume controls to a preview target or compatible local media renderer")
                            .foregroundStyle(.secondary)
                        Label {
                            Text(model.productStatus)
                        } icon: {
                            Image(systemName: "hammer")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                StatusCard(model: model)

                VStack(alignment: .leading, spacing: 14) {
                    Text("How setup will work")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    SetupStepRow(
                        number: 1,
                        title: "Choose a media target",
                        detail: "Open Settings to create an in-process preview target or explicitly select a compatible renderer discovered on your local network."
                    )
                    SetupStepRow(
                        number: 2,
                        title: "Allow volume key access",
                        detail: model.inputMonitoringSetupDetail
                    )
                    Button("Open Volume Key Settings") {
                        openSettings()
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel("Open Volume Key Settings")
                    .accessibilityHint("Opens Media Control Relay Settings")
                    SetupStepRow(
                        number: 3,
                        title: "Verify volume routing",
                        detail: "Use Settings to review activation matching, command counts, and the selected target's connection status."
                    )
                    if model.remoteControl != nil {
                        SetupStepRow(
                            number: 4,
                            title: "Connect an Apple TV",
                            detail: "Use the Apple TV tab in Settings to discover, pair, and recover the optional local remote connection."
                        )
                    }
                }

                Text("Configuration stays on this Mac. Local-network discovery shows generic renderer labels only, and Media Control Relay contacts only the renderer you explicitly select for volume control.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .frame(
            minWidth: 460,
            idealWidth: 560,
            maxWidth: 720,
            minHeight: 360,
            idealHeight: 520,
            maxHeight: 600
        )
    }
}

private struct StatusCard: View {
    let model: RelayAppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.statusCopy.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusCopy.title)
                    .font(.headline)
                Text(model.statusCopy.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
                .accessibilityLabel("Step \(number)")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
