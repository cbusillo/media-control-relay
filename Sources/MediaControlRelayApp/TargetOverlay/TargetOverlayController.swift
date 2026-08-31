import AppKit
import CoreGraphics
import MediaControlCore

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

        let frame = OverlayPanelGeometry.topTrailingRect(
            panelSize: TargetOverlayMetrics.panelSize,
            on: placement.screen,
            topInset: TargetOverlayMetrics.nativeHUDTopInset,
            trailingInset: TargetOverlayMetrics.nativeHUDTrailingInset
        )
        panelPresenter.show(
            state: latestPresentationState,
            outputName: overlayTitle(for: latestRouteSnapshot.audioOutput?.name),
            frame: frame
        )
    }

    private func overlayTitle(for outputName: String?) -> String {
        guard let outputName else {
            return "Media Volume"
        }
        let normalizedName = outputName
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalizedName.isEmpty ? "Media Volume" : normalizedName
    }

    @objc private func screenParametersChanged() {
        refreshPresentation()
    }
}
