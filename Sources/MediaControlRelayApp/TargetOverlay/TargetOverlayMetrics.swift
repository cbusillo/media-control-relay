import AppKit
import MediaControlCore

enum TargetOverlayMetrics {
    static let panelSize = OverlaySize(width: 294, height: 64)
    static let surfaceMargin: Double = 8
    static let windowSize = OverlaySize(
        width: panelSize.width + surfaceMargin * 2,
        height: panelSize.height + surfaceMargin * 2
    )
    static let nativeHUDTopInset: Double = 10
    static let nativeHUDTrailingInset: Double = 16
    static let windowLevel = NSWindow.Level.statusBar
    static let cornerRadius: Double = 20
    static let horizontalPadding: Double = 16
    static let topPadding: Double = 10.5
    static let rowSpacing: Double = 9
    static let trackRowSpacing: Double = 8
    static let captionPointSize: Double = 13
    static let captionRowHeight: Double = 16
    static let trackRowHeight: Double = 16
    static let glyphPointSize: Double = 12
    static let leadingGlyphSlotWidth: Double = 8
    static let trailingGlyphSlotWidth: Double = 16
    static let trackHeight: Double = 4
    static let tickTopGap: Double = 3
    static let tickDiameter: Double = 2
    static let tickEndInset: Double = 4
    static let nativeHUDTickCount = 17
    static let trackGroupHeight = trackHeight + tickTopGap + tickDiameter

    static func windowFrame(containing visualFrame: OverlayRect) -> OverlayRect {
        OverlayRect(
            x: visualFrame.origin.x - surfaceMargin,
            y: visualFrame.origin.y - surfaceMargin,
            width: visualFrame.size.width + surfaceMargin * 2,
            height: visualFrame.size.height + surfaceMargin * 2
        )
    }
}
