import AppKit
import CoreGraphics
import MediaControlCore
import SwiftUI

enum TargetOverlayMetrics {
    static let panelSize = OverlaySize(width: 224, height: 76)
    static let bottomInset: Double = 24
    static let windowLevel = NSWindow.Level.statusBar
}

@MainActor
protocol TargetOverlayPresenting: AnyObject {
    func update(
        presentationState: MediaTargetPresentationState,
        routeSnapshot: RouteSnapshot,
        activationRule: ActivationRule?
    )
}

@MainActor
final class InactiveTargetOverlayPresenter: TargetOverlayPresenting {
    func update(
        presentationState _: MediaTargetPresentationState,
        routeSnapshot _: RouteSnapshot,
        activationRule _: ActivationRule?
    ) {}
}

enum DisplayStableIdentifier {
    static func forDisplayID(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    static func forScreen(_ screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return forDisplayID(CGDirectDisplayID(screenNumber.uint32Value))
    }
}

@MainActor
protocol OverlayScreenProviding {
    func screens() -> [OverlayScreenDescriptor]
}

@MainActor
struct LiveOverlayScreenProvider: OverlayScreenProviding {
    func screens() -> [OverlayScreenDescriptor] {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.map { screen in
            OverlayScreenDescriptor(
                stableIdentifier: DisplayStableIdentifier.forScreen(screen),
                name: screen.localizedName,
                frame: overlayRect(screen.frame),
                visibleFrame: overlayRect(screen.visibleFrame),
                backingScaleFactor: screen.backingScaleFactor,
                containsPointer: screen.frame.contains(pointerLocation),
                isMain: screen == NSScreen.main
            )
        }
    }

    private func overlayRect(_ rect: NSRect) -> OverlayRect {
        OverlayRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

@MainActor
protocol TargetOverlayPanelPresenting: AnyObject {
    func show(state: MediaTargetPresentationState, frame: OverlayRect)
    func hide()
}

@MainActor
final class TargetOverlayController: NSObject, TargetOverlayPresenting {
    private let screenProvider: any OverlayScreenProviding
    private let panelPresenter: any TargetOverlayPanelPresenting
    private let notificationCenter: NotificationCenter
    private var latestPresentationState: MediaTargetPresentationState = .hidden
    private var latestRouteSnapshot = RouteSnapshot(audioOutput: nil, displays: [])
    private var latestActivationRule: ActivationRule?

    init(
        screenProvider: any OverlayScreenProviding = LiveOverlayScreenProvider(),
        panelPresenter: any TargetOverlayPanelPresenting = TargetOverlayPanelPresenter(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.screenProvider = screenProvider
        self.panelPresenter = panelPresenter
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func update(
        presentationState: MediaTargetPresentationState,
        routeSnapshot: RouteSnapshot,
        activationRule: ActivationRule?
    ) {
        latestPresentationState = presentationState
        latestRouteSnapshot = routeSnapshot
        latestActivationRule = activationRule
        refreshPresentation()
    }

    private func refreshPresentation() {
        guard latestPresentationState.isVisible,
              let latestActivationRule,
              let placement = OverlayPlacementResolver.resolve(
                  activationRule: latestActivationRule,
                  routeSnapshot: latestRouteSnapshot,
                  screens: screenProvider.screens()
              ) else {
            panelPresenter.hide()
            return
        }

        let frame = OverlayPanelGeometry.bottomCenterRect(
            panelSize: TargetOverlayMetrics.panelSize,
            on: placement.screen,
            bottomInset: TargetOverlayMetrics.bottomInset
        )
        panelPresenter.show(state: latestPresentationState, frame: frame)
    }

    @objc private func screenParametersChanged() {
        refreshPresentation()
    }
}

@MainActor
final class TargetOverlayPanelPresenter: TargetOverlayPanelPresenting {
    let panel: TargetOverlayPanel
    private let contentView: NSHostingView<TargetOverlayContentView>

    init(panel: TargetOverlayPanel = TargetOverlayPanel()) {
        self.panel = panel
        contentView = NSHostingView(rootView: TargetOverlayContentView(state: .hidden))
        panel.contentView = contentView
    }

    func show(state: MediaTargetPresentationState, frame: OverlayRect) {
        contentView.rootView = TargetOverlayContentView(state: state)
        panel.setFrame(nsRect(frame), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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
        level = TargetOverlayMetrics.windowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct TargetOverlayContentView: View {
    let state: MediaTargetPresentationState

    var body: some View {
        Text(label)
            .frame(
                width: TargetOverlayMetrics.panelSize.width,
                height: TargetOverlayMetrics.panelSize.height
            )
    }

    private var label: String {
        switch state {
        case .hidden, .suspended, .routeLost:
            ""
        case .pendingCold, .pendingBaseline:
            "Adjusting volume"
        case let .confirmed(value), let .muted(value), let .rail(_, value), let .failed(value?):
            value.isMuted ? "Muted" : "Volume \(value.percentage)%"
        case .failed(nil):
            "Volume unavailable"
        }
    }
}
