import AppKit
import SwiftUI

struct SetupView: View {
    @Environment(\.openSettings) private var openSettings
    let model: RelayAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Media Control Relay")
                        .font(.largeTitle.weight(.semibold))
                    Text("Preview local volume routing without connecting to a media device")
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
                    title: "Create a preview target",
                    detail: "Record routed volume actions in-process without controlling a TV or interfering with normal Mac volume behavior."
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
                    title: "Review recorded commands",
                    detail: "Use Settings to see activation matching and recorded or unrecorded preview actions."
                )
            }

            Spacer()

            Text(model.previewTargetExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
