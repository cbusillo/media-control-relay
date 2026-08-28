import AppKit
import MediaControlCore
import SwiftUI

@MainActor
protocol TargetOverlayPanelPresenting: AnyObject {
    func show(state: MediaTargetPresentationState, frame: OverlayRect)
    func hide()
}

@MainActor
final class TargetOverlayPanelPresenter: NSObject, TargetOverlayPanelPresenting {
    let panel: TargetOverlayPanel
    private let contentView: NSHostingView<TargetOverlayContentView>
    private let accessibilityDisplayOptionsProvider: any TargetOverlayAccessibilityDisplayOptionsProviding
    private let notificationCenter: NotificationCenter
    private(set) var accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions
    private var currentVisualState = TargetOverlayVisualState(presentationState: .hidden)

    init(
        panel: TargetOverlayPanel = TargetOverlayPanel(),
        accessibilityDisplayOptionsProvider: any TargetOverlayAccessibilityDisplayOptionsProviding =
            LiveTargetOverlayAccessibilityDisplayOptionsProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.panel = panel
        self.accessibilityDisplayOptionsProvider = accessibilityDisplayOptionsProvider
        self.notificationCenter = notificationCenter
        accessibilityDisplayOptions = accessibilityDisplayOptionsProvider.accessibilityDisplayOptions
        contentView = NSHostingView(
            rootView: TargetOverlayContentView(
                visualState: currentVisualState,
                accessibilityDisplayOptions: accessibilityDisplayOptions
            )
        )
        super.init()
        panel.contentView = contentView
        contentView.setAccessibilityElement(false)
        panel.apply(accessibilityDisplayOptions: accessibilityDisplayOptions)
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

    func show(state: MediaTargetPresentationState, frame: OverlayRect) {
        currentVisualState = TargetOverlayVisualState(presentationState: state)
        updateContentView()
        panel.setFrame(nsRect(frame), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func refreshAccessibilityDisplayOptions() {
        accessibilityDisplayOptions = accessibilityDisplayOptionsProvider.accessibilityDisplayOptions
        panel.apply(accessibilityDisplayOptions: accessibilityDisplayOptions)
        updateContentView()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        refreshAccessibilityDisplayOptions()
    }

    private func updateContentView() {
        contentView.rootView = TargetOverlayContentView(
            visualState: currentVisualState,
            accessibilityDisplayOptions: accessibilityDisplayOptions
        )
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
                width: TargetOverlayMetrics.panelSize.width,
                height: TargetOverlayMetrics.panelSize.height
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
        ignoresMouseEvents = true
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions) {
        hasShadow = !accessibilityDisplayOptions.increaseContrast
    }
}
