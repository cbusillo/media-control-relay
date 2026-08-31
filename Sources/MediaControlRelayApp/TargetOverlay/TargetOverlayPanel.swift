import AppKit
import MediaControlCore
import SwiftUI

@MainActor
protocol TargetOverlayPanelPresenting: AnyObject {
    func show(state: MediaTargetPresentationState, outputName: String, frame: OverlayRect)
    func hide()
}

@MainActor
final class TargetOverlayPanelPresenter: NSObject, TargetOverlayPanelPresenting {
    let panel: TargetOverlayPanel
    private(set) var surfaceView: NSView?
    private(set) var contentView: NSHostingView<TargetOverlayContentView>
    private let accessibilityDisplayOptionsProvider: any TargetOverlayAccessibilityDisplayOptionsProviding
    private let notificationCenter: NotificationCenter
    private(set) var accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions
    private var currentVisualState = TargetOverlayVisualState(presentationState: .hidden)
    private var currentOutputName = "Media Volume"

    init(
        panel: TargetOverlayPanel = TargetOverlayPanel(),
        accessibilityDisplayOptionsProvider: any TargetOverlayAccessibilityDisplayOptionsProviding =
            LiveTargetOverlayAccessibilityDisplayOptionsProvider(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.panel = panel
        self.accessibilityDisplayOptionsProvider = accessibilityDisplayOptionsProvider
        self.notificationCenter = notificationCenter
        accessibilityDisplayOptions = accessibilityDisplayOptionsProvider.accessibilityDisplayOptions
        contentView = NSHostingView(
            rootView: TargetOverlayContentView(
                visualState: currentVisualState,
                outputName: currentOutputName,
                accessibilityDisplayOptions: accessibilityDisplayOptions,
                surfaceStyle: .contentOnly
            )
        )
        super.init()
        contentView.sizingOptions = []
        contentView.clipsToBounds = false
        contentView.autoresizingMask = [.width, .height]
        contentView.setAccessibilityElement(false)
        installSurface()
        updateContentView()
        notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func show(state: MediaTargetPresentationState, outputName: String, frame: OverlayRect) {
        currentVisualState = TargetOverlayVisualState(presentationState: state)
        currentOutputName = outputName
        updateContentView()
        panel.setFrame(nsRect(TargetOverlayMetrics.windowFrame(containing: frame)), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func refreshAccessibilityDisplayOptions() {
        let newOptions = accessibilityDisplayOptionsProvider.accessibilityDisplayOptions
        guard newOptions != accessibilityDisplayOptions else {
            return
        }
        let previousSurfaceStyle = surfaceStyle
        accessibilityDisplayOptions = newOptions
        if surfaceStyle != previousSurfaceStyle {
            installSurface()
        }
        updateContentView()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        refreshAccessibilityDisplayOptions()
    }

    private func updateContentView() {
        contentView.rootView = TargetOverlayContentView(
            visualState: currentVisualState,
            outputName: currentOutputName,
            accessibilityDisplayOptions: accessibilityDisplayOptions,
            surfaceStyle: surfaceStyle
        )
    }

    private var surfaceStyle: TargetOverlaySurfaceStyle {
        if accessibilityDisplayOptions.reduceTransparency {
            return .opaque
        }
        if #available(macOS 26.0, *) {
            return .contentOnly
        }
        return .regularMaterial
    }

    private func installSurface() {
        if #available(macOS 26.0, *), let glass = surfaceView as? NSGlassEffectView {
            glass.contentView = nil
        }
        contentView.removeFromSuperview()
        surfaceView?.removeFromSuperview()

        let rootView = NSView(frame: NSRect(
            origin: .zero,
            size: NSSize(
                width: TargetOverlayMetrics.windowSize.width,
                height: TargetOverlayMetrics.windowSize.height
            )
        ))
        rootView.autoresizingMask = [.width, .height]
        rootView.clipsToBounds = false
        rootView.setAccessibilityElement(false)
        panel.contentView = rootView

        let visualFrame = NSRect(
            x: TargetOverlayMetrics.surfaceMargin,
            y: TargetOverlayMetrics.surfaceMargin,
            width: TargetOverlayMetrics.panelSize.width,
            height: TargetOverlayMetrics.panelSize.height
        )
        if surfaceStyle == .contentOnly, #available(macOS 26.0, *) {
            let glass = makeGlassEffectView(frame: visualFrame)
            contentView.frame = glass.bounds
            glass.contentView = contentView
            rootView.addSubview(glass)
            surfaceView = glass
        } else {
            contentView.frame = visualFrame
            rootView.addSubview(contentView)
            surfaceView = contentView
        }
    }

    @available(macOS 26.0, *)
    private func makeGlassEffectView(frame: NSRect) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: frame)
        glass.style = .regular
        glass.cornerRadius = TargetOverlayMetrics.cornerRadius
        glass.tintColor = nil
        glass.autoresizingMask = []
        glass.setAccessibilityElement(false)
        let interactiveSetter = NSSelectorFromString("setEffectIsInteractive:")
        if #available(macOS 27.0, *), glass.responds(to: interactiveSetter) {
            glass.setValue(false, forKey: "effectIsInteractive")
        }
        return glass
    }

    private func nsRect(_ rect: OverlayRect) -> NSRect {
        NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

@MainActor
final class TargetOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: TargetOverlayMetrics.windowSize.width,
                height: TargetOverlayMetrics.windowSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = TargetOverlayMetrics.windowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
