import AppKit
import MediaControlCore
import Testing
@testable import Media_Control_Relay

@Suite("Target overlay controller", .serialized)
@MainActor
struct TargetOverlayControllerTests {
    @Test("Visible states show and update one panel presenter")
    func visibleStatesShowAndUpdate() {
        let screen = makeScreen(identifier: "main")
        let screenProvider = OverlayScreenProviderStub(screens: [screen])
        let panelPresenter = OverlayPanelPresenterSpy()
        let controller = TargetOverlayController(
            screenProvider: screenProvider,
            panelPresenter: panelPresenter,
            notificationCenter: NotificationCenter()
        )

        controller.update(
            presentationState: .confirmed(makePresentationValue()),
            routeSnapshot: makeOverlayRoute(),
            activationRule: makeActivationRule()
        )
        controller.update(
            presentationState: .muted(makePresentationValue(isMuted: true)),
            routeSnapshot: makeOverlayRoute(),
            activationRule: makeActivationRule()
        )

        #expect(panelPresenter.showStates == [
            .confirmed(makePresentationValue()),
            .muted(makePresentationValue(isMuted: true)),
        ])
        #expect(panelPresenter.frames == [
            OverlayPanelGeometry.bottomCenterRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: screen,
                bottomInset: TargetOverlayMetrics.bottomInset
            ),
            OverlayPanelGeometry.bottomCenterRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: screen,
                bottomInset: TargetOverlayMetrics.bottomInset
            ),
        ])
        #expect(panelPresenter.hideCount == 0)
    }

    @Test("Hidden and invalidated states hide the panel")
    func hiddenAndInvalidatedStatesHide() {
        let screenProvider = OverlayScreenProviderStub(screens: [makeScreen(identifier: "main")])
        let panelPresenter = OverlayPanelPresenterSpy()
        let controller = TargetOverlayController(
            screenProvider: screenProvider,
            panelPresenter: panelPresenter,
            notificationCenter: NotificationCenter()
        )

        for state in [
            MediaTargetPresentationState.hidden,
            .suspended,
            .routeLost,
        ] {
            controller.update(
                presentationState: state,
                routeSnapshot: makeOverlayRoute(),
                activationRule: makeActivationRule()
            )
        }
        controller.update(
            presentationState: .confirmed(makePresentationValue()),
            routeSnapshot: makeOverlayRoute(),
            activationRule: nil
        )
        screenProvider.currentScreens = []
        controller.update(
            presentationState: .confirmed(makePresentationValue()),
            routeSnapshot: makeOverlayRoute(),
            activationRule: makeActivationRule()
        )

        #expect(panelPresenter.showStates.isEmpty)
        #expect(panelPresenter.hideCount == 5)
    }

    @Test("Fallback placement uses single, pointer, main, and first screens")
    func fallbackPlacementOrder() {
        let single = makeScreen(identifier: "single", x: 0)
        let pointer = makeScreen(identifier: "pointer", x: 1_000, containsPointer: true)
        let main = makeScreen(identifier: "main", x: 2_000, isMain: true)
        let first = makeScreen(identifier: "first", x: 3_000)
        let screenProvider = OverlayScreenProviderStub(screens: [])
        let panelPresenter = OverlayPanelPresenterSpy()
        let controller = TargetOverlayController(
            screenProvider: screenProvider,
            panelPresenter: panelPresenter,
            notificationCenter: NotificationCenter()
        )

        let scenarios: [([OverlayScreenDescriptor], OverlayScreenDescriptor)] = [
            ([single], single),
            ([main, pointer], pointer),
            ([first, main], main),
            ([first, makeScreen(identifier: "second", x: 4_000)], first),
        ]

        for (screens, expectedScreen) in scenarios {
            screenProvider.currentScreens = screens
            controller.update(
                presentationState: .confirmed(makePresentationValue()),
                routeSnapshot: makeOverlayRoute(),
                activationRule: makeActivationRule()
            )
            #expect(panelPresenter.frames.last == OverlayPanelGeometry.bottomCenterRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: expectedScreen,
                bottomInset: TargetOverlayMetrics.bottomInset
            ))
        }
    }

    @Test("Screen changes reposition the existing panel presenter")
    func screenChangesRepositionWithoutNewPresenter() {
        let first = makeScreen(identifier: "first", x: 0)
        let second = makeScreen(identifier: "second", x: 1_000)
        let screenProvider = OverlayScreenProviderStub(screens: [first])
        let panelPresenter = OverlayPanelPresenterSpy()
        let notificationCenter = NotificationCenter()
        let controller = TargetOverlayController(
            screenProvider: screenProvider,
            panelPresenter: panelPresenter,
            notificationCenter: notificationCenter
        )

        controller.update(
            presentationState: .confirmed(makePresentationValue()),
            routeSnapshot: makeOverlayRoute(),
            activationRule: makeActivationRule()
        )
        screenProvider.currentScreens = [second]
        notificationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(panelPresenter.showStates.count == 2)
        #expect(panelPresenter.frames == [
            OverlayPanelGeometry.bottomCenterRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: first,
                bottomInset: TargetOverlayMetrics.bottomInset
            ),
            OverlayPanelGeometry.bottomCenterRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: second,
                bottomInset: TargetOverlayMetrics.bottomInset
            ),
        ])
        #expect(panelPresenter.hideCount == 0)
        _ = controller
    }

    @Test("Panel configuration remains nonactivating and initially unordered")
    func panelConfiguration() {
        let panel = TargetOverlayPanel()

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == TargetOverlayMetrics.windowLevel)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.isAccessibilityElement())
        #expect(!panel.isVisible)
    }
}

@MainActor
private final class OverlayScreenProviderStub: OverlayScreenProviding {
    var currentScreens: [OverlayScreenDescriptor]

    init(screens: [OverlayScreenDescriptor]) {
        currentScreens = screens
    }

    func screens() -> [OverlayScreenDescriptor] {
        currentScreens
    }
}

@MainActor
private final class OverlayPanelPresenterSpy: TargetOverlayPanelPresenting {
    private(set) var showStates: [MediaTargetPresentationState] = []
    private(set) var frames: [OverlayRect] = []
    private(set) var hideCount = 0

    func show(state: MediaTargetPresentationState, frame: OverlayRect) {
        showStates.append(state)
        frames.append(frame)
    }

    func hide() {
        hideCount += 1
    }
}

private func makePresentationValue(isMuted: Bool = false) -> MediaTargetPresentationValue {
    MediaTargetPresentationValue(
        normalizedLevel: 0.5,
        confirmedVolume: 5,
        displayedVolume: 5,
        isMuted: isMuted,
        minimumVolume: 0,
        maximumVolume: 10,
        volumeStep: 1
    )
}

private func makeActivationRule() -> ActivationRule {
    ActivationRule(audioOutputMatch: "Fixture Output", requiresDisplay: false)
}

private func makeOverlayRoute() -> RouteSnapshot {
    RouteSnapshot(
        audioOutput: AudioOutputSnapshot(name: "Fixture Output", transportKind: .display),
        displays: []
    )
}

private func makeScreen(
    identifier: String,
    x: Double = 0,
    containsPointer: Bool = false,
    isMain: Bool = false
) -> OverlayScreenDescriptor {
    OverlayScreenDescriptor(
        stableIdentifier: identifier,
        name: identifier,
        frame: OverlayRect(x: x, y: 0, width: 900, height: 600),
        visibleFrame: OverlayRect(x: x, y: 0, width: 900, height: 600),
        backingScaleFactor: 2,
        containsPointer: containsPointer,
        isMain: isMain
    )
}
