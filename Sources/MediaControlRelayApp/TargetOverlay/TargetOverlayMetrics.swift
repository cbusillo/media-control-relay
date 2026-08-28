import AppKit
import MediaControlCore

enum TargetOverlayMetrics {
    static let panelSize = OverlaySize(width: 224, height: 76)
    static let nativeHUDBottomInset: Double = 124
    static let bottomInset = nativeHUDBottomInset
    static let windowLevel = NSWindow.Level.statusBar
    static let cornerRadius: Double = 18
    static let horizontalPadding: Double = 16
    static let verticalPadding: Double = 14
    static let trackHeight: Double = 6
}
