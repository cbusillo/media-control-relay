import AppKit
import SwiftUI

@MainActor
struct TargetOverlayAccessibilityDisplayOptions: Equatable {
    let reduceTransparency: Bool
    let increaseContrast: Bool
}

@MainActor
protocol TargetOverlayAccessibilityDisplayOptionsProviding {
    var accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions { get }
}

@MainActor
struct LiveTargetOverlayAccessibilityDisplayOptionsProvider:
    TargetOverlayAccessibilityDisplayOptionsProviding
{
    var accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions {
        TargetOverlayAccessibilityDisplayOptions(
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

struct TargetOverlayContentView: View {
    let visualState: TargetOverlayVisualState
    let accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: TargetOverlayMetrics.cornerRadius,
            style: .continuous
        )

        ZStack {
            panelSurface(in: shape)
            shape.strokeBorder(borderColor, lineWidth: borderWidth)

            if visualState.isVisible {
                HStack(spacing: 12) {
                    Image(systemName: visualState.glyph?.systemName ?? "speaker.wave.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(glyphColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        volumeTrack
                        caption
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(captionColor)
                    }
                }
                .padding(.horizontal, TargetOverlayMetrics.horizontalPadding)
                .padding(.vertical, TargetOverlayMetrics.verticalPadding)
            }
        }
        .frame(
            width: TargetOverlayMetrics.panelSize.width,
            height: TargetOverlayMetrics.panelSize.height
        )
        .accessibilityHidden(true)
    }

    private var volumeTrack: some View {
        GeometryReader { proxy in
            let levelWidth = proxy.size.width * (visualState.level ?? 0)
            Capsule(style: .continuous)
                .fill(trackColor)
                .overlay(alignment: .leading) {
                    if visualState.level != nil {
                        Capsule(style: .continuous)
                            .fill(levelColor)
                            .frame(width: levelWidth)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(trackBorderColor, lineWidth: borderWidth)
                }
        }
        .frame(height: TargetOverlayMetrics.trackHeight)
    }

    @ViewBuilder
    private var caption: some View {
        switch visualState.caption {
        case .adjusting:
            Text("Adjusting volume")
        case let .percentage(level):
            Text(level, format: .percent.precision(.fractionLength(0)))
        case .muted:
            Text("Muted")
        case .unavailable:
            Text("Unavailable")
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func panelSurface(in shape: RoundedRectangle) -> some View {
        if accessibilityDisplayOptions.reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private var glyphColor: Color {
        switch visualState.glyph {
        case .warning:
            .secondary
        case .speaker, .speakerLow, .speakerMedium, .speakerHigh, .muted, nil:
            .primary
        }
    }

    private var levelColor: Color {
        switch visualState.levelTreatment {
        case .confirmed:
            Color.accentColor
        case .pending:
            Color.accentColor.opacity(0.58)
        case .muted, .frozen:
            .secondary
        case .none:
            .clear
        }
    }

    private var trackColor: Color {
        accessibilityDisplayOptions.increaseContrast
            ? Color.primary.opacity(0.22)
            : Color.secondary.opacity(0.18)
    }

    private var trackBorderColor: Color {
        accessibilityDisplayOptions.increaseContrast
            ? Color.primary.opacity(0.48)
            : Color.secondary.opacity(0.24)
    }

    private var borderColor: Color {
        accessibilityDisplayOptions.increaseContrast
            ? Color.primary.opacity(0.6)
            : Color.secondary.opacity(0.24)
    }

    private var borderWidth: Double {
        accessibilityDisplayOptions.increaseContrast ? 1.5 : 1
    }

    private var captionColor: Color {
        accessibilityDisplayOptions.increaseContrast ? .primary : .secondary
    }
}
