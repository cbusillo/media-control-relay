import AppKit
import SwiftUI

struct SetupView: View {
    @Environment(\.openSettings) private var openSettings
    let model: BridgeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TV Volume Bridge")
                        .font(.largeTitle.weight(.semibold))
                    Text("Use your Mac’s volume keys to control a compatible Samsung TV")
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

                SetupStepRow(
                    number: 1,
                    title: "Choose your TV",
                    detail: "Find a compatible TV on your network or add it manually."
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
                SetupStepRow(
                    number: 3,
                    title: "Test your controls",
                    detail: "Confirm that your Mac controls the TV only while you’re using it."
                )
            }

            Spacer()

            Text("TV setup isn’t available in this preview.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshInputMonitoring()
        }
    }
}

private struct StatusCard: View {
    let model: BridgeAppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.bridgeState.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.bridgeState.title)
                    .font(.headline)
                Text(model.bridgeState.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            }
        }
        .accessibilityElement(children: .combine)
    }
}
