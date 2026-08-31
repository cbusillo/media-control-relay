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

enum TargetOverlaySurfaceStyle: Equatable {
    case contentOnly
    case regularMaterial
    case opaque
}

struct TargetOverlayContentView: View {
    let visualState: TargetOverlayVisualState
    let outputName: String
    let accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions
    let surfaceStyle: TargetOverlaySurfaceStyle
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: TargetOverlayMetrics.cornerRadius,
            style: .continuous
        )

        renderedSurface(in: shape)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func renderedSurface(in shape: RoundedRectangle) -> some View {
        switch surfaceStyle {
        case .opaque:
            overlayContent
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { panelBorder(in: shape) }
        case .regularMaterial:
            overlayContent
                .background(.regularMaterial, in: shape)
                .overlay { panelBorder(in: shape) }
        case .contentOnly:
            overlayContent
                .overlay { panelBorder(in: shape) }
        }
    }

    private var overlayContent: some View {
        ZStack(alignment: .topLeading) {
            if visualState.isVisible {
                VStack(alignment: .leading, spacing: TargetOverlayMetrics.rowSpacing) {
                    Text(outputName)
                        .font(.system(
                            size: TargetOverlayMetrics.captionPointSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: TargetOverlayMetrics.captionRowHeight,
                            maxHeight: TargetOverlayMetrics.captionRowHeight,
                            alignment: .leading
                        )

                    trackRow
                }
                .padding(.horizontal, TargetOverlayMetrics.horizontalPadding)
                .padding(.top, TargetOverlayMetrics.topPadding)
            }
        }
        .frame(
            width: TargetOverlayMetrics.panelSize.width,
            height: TargetOverlayMetrics.panelSize.height,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func panelBorder(in shape: RoundedRectangle) -> some View {
        if panelBorderWidth > 0 {
            shape.strokeBorder(panelBorderColor, lineWidth: panelBorderWidth)
        }
    }

    private var trackRow: some View {
        HStack(spacing: TargetOverlayMetrics.trackRowSpacing) {
            Image(systemName: leadingGlyphSystemName)
                .font(.system(size: TargetOverlayMetrics.glyphPointSize, weight: .semibold))
                .foregroundStyle(leadingGlyphColor)
                .frame(
                    width: TargetOverlayMetrics.leadingGlyphSlotWidth,
                    alignment: .leading
                )

            volumeTrack

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: TargetOverlayMetrics.glyphPointSize, weight: .semibold))
                .foregroundStyle(trailingGlyphColor)
                .frame(
                    width: TargetOverlayMetrics.trailingGlyphSlotWidth,
                    alignment: .trailing
                )
        }
        .frame(height: TargetOverlayMetrics.trackRowHeight)
    }

    private var volumeTrack: some View {
        GeometryReader { proxy in
            let levelWidth = alignedLevelWidth(availableWidth: proxy.size.width)
            VStack(spacing: TargetOverlayMetrics.tickTopGap) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .frame(width: proxy.size.width, height: TargetOverlayMetrics.trackHeight)
                    .overlay(alignment: .leading) {
                        if visualState.level != nil, levelWidth > 0 {
                            Capsule(style: .continuous)
                                .fill(levelColor)
                                .frame(width: levelWidth)
                        }
                    }
                    .overlay {
                        if trackBorderWidth > 0 {
                            Capsule(style: .continuous)
                                .strokeBorder(trackBorderColor, lineWidth: trackBorderWidth)
                        }
                    }

                HStack(spacing: 0) {
                    ForEach(0 ..< TargetOverlayMetrics.nativeHUDTickCount, id: \.self) { index in
                        Circle()
                            .fill(tickColor)
                            .frame(
                                width: TargetOverlayMetrics.tickDiameter,
                                height: TargetOverlayMetrics.tickDiameter
                            )
                        if index + 1 < TargetOverlayMetrics.nativeHUDTickCount {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, TargetOverlayMetrics.tickEndInset)
                .frame(width: proxy.size.width, height: TargetOverlayMetrics.tickDiameter)
            }
            .frame(width: proxy.size.width, height: TargetOverlayMetrics.trackGroupHeight)
        }
        .frame(height: TargetOverlayMetrics.trackGroupHeight)
    }

    private var leadingGlyphSystemName: String {
        switch visualState.glyph {
        case .muted, .warning:
            visualState.glyph?.systemName ?? "speaker.fill"
        case .speaker, .speakerLow, .speakerMedium, .speakerHigh, nil:
            "speaker.fill"
        }
    }

    private func alignedLevelWidth(availableWidth: CGFloat) -> CGFloat {
        guard let level = visualState.level, level > 0 else {
            return 0
        }
        let scale = max(displayScale, 1)
        let alignedWidth = (availableWidth * CGFloat(level) * scale).rounded() / scale
        return min(
            max(alignedWidth, CGFloat(TargetOverlayMetrics.trackHeight)),
            availableWidth
        )
    }

    private var leadingGlyphColor: Color {
        switch visualState.glyph {
        case .warning:
            .secondary
        case .speaker, .speakerLow, .speakerMedium, .speakerHigh, .muted, nil:
            .primary
        }
    }

    private var trailingGlyphColor: Color {
        .primary
    }

    private var levelColor: Color {
        switch visualState.levelTreatment {
        case .confirmed:
            .primary
        case .pending:
            Color.primary.opacity(0.45)
        case .muted:
            Color.secondary.opacity(0.55)
        case .frozen:
            Color.secondary.opacity(0.35)
        case .none:
            .clear
        }
    }

    private var trackColor: Color {
        accessibilityDisplayOptions.increaseContrast
            ? Color.primary.opacity(0.28)
            : Color.primary.opacity(0.15)
    }

    private var trackBorderColor: Color {
        Color.primary.opacity(0.55)
    }

    private var trackBorderWidth: Double {
        accessibilityDisplayOptions.increaseContrast ? 1 : 0
    }

    private var tickColor: Color {
        Color.primary.opacity(accessibilityDisplayOptions.increaseContrast ? 0.45 : 0.28)
    }

    private var panelBorderColor: Color {
        if accessibilityDisplayOptions.increaseContrast {
            return Color.primary.opacity(0.6)
        }
        if accessibilityDisplayOptions.reduceTransparency {
            return Color(nsColor: .separatorColor)
        }
        return .clear
    }

    private var panelBorderWidth: Double {
        if accessibilityDisplayOptions.increaseContrast {
            return 1.5
        }
        return accessibilityDisplayOptions.reduceTransparency ? 1 : 0
    }
}
