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
        #expect(panelPresenter.outputNames == ["Fixture Output", "Fixture Output"])
        let expectedFrame = OverlayRect(x: 590, y: 526, width: 294, height: 64)
        #expect(panelPresenter.frames == [
            expectedFrame,
            expectedFrame,
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
            #expect(panelPresenter.frames.last == OverlayPanelGeometry.topTrailingRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: expectedScreen,
                topInset: TargetOverlayMetrics.nativeHUDTopInset,
                trailingInset: TargetOverlayMetrics.nativeHUDTrailingInset
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
            OverlayPanelGeometry.topTrailingRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: first,
                topInset: TargetOverlayMetrics.nativeHUDTopInset,
                trailingInset: TargetOverlayMetrics.nativeHUDTrailingInset
            ),
            OverlayPanelGeometry.topTrailingRect(
                panelSize: TargetOverlayMetrics.panelSize,
                on: second,
                topInset: TargetOverlayMetrics.nativeHUDTopInset,
                trailingInset: TargetOverlayMetrics.nativeHUDTrailingInset
            ),
        ])
        #expect(panelPresenter.hideCount == 0)
        _ = controller
    }

    @Test("Panel configuration remains nonactivating and initially unordered")
    func panelConfiguration() {
        let panel = TargetOverlayPanel()

        #expect(panel.frame.size == NSSize(
            width: TargetOverlayMetrics.windowSize.width,
            height: TargetOverlayMetrics.windowSize.height
        ))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == TargetOverlayMetrics.windowLevel)
        #expect(panel.isFloatingPanel)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.isMovable)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.animationBehavior == .none)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(!panel.isAccessibilityElement())
        #expect(!panel.hasShadow)
        #expect(!panel.isVisible)
    }

    @Test("Native-style metrics compose the fixed panel")
    func nativeStyleMetricsComposePanel() {
        #expect(
            TargetOverlayMetrics.topPadding +
                TargetOverlayMetrics.captionRowHeight +
                TargetOverlayMetrics.rowSpacing +
                TargetOverlayMetrics.trackRowHeight < TargetOverlayMetrics.panelSize.height
        )
        #expect(TargetOverlayMetrics.cornerRadius <= TargetOverlayMetrics.panelSize.height / 2)
        #expect(TargetOverlayMetrics.leadingGlyphSlotWidth <= TargetOverlayMetrics.glyphPointSize)
        #expect(TargetOverlayMetrics.trailingGlyphSlotWidth >= TargetOverlayMetrics.glyphPointSize)
        #expect(TargetOverlayMetrics.trackGroupHeight <= TargetOverlayMetrics.trackRowHeight)
        #expect(TargetOverlayMetrics.nativeHUDTickCount == 17)
        #expect(TargetOverlayMetrics.windowSize.width == 310)
        #expect(TargetOverlayMetrics.windowSize.height == 80)

        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: TargetOverlayMetrics.glyphPointSize,
            weight: .semibold
        )
        for glyph in [TargetOverlayGlyph.speaker, .muted, .warning] {
            let image = NSImage(
                systemSymbolName: glyph.systemName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(symbolConfiguration)
            #expect(image != nil)
            #expect(image?.size.width ?? .infinity <
                TargetOverlayMetrics.leadingGlyphSlotWidth +
                    TargetOverlayMetrics.trackRowSpacing)
        }
    }

    @Test("Panel presenter shows, positions, and hides the reusable panel")
    func panelPresenterShowAndHide() {
        let panel = TargetOverlayPanel()
        let presenter = TargetOverlayPanelPresenter(
            panel: panel,
            notificationCenter: NotificationCenter()
        )
        #expect(panel.contentView?.clipsToBounds == false)
        let frame = OverlayRect(
            origin: OverlayPoint(x: -10_000, y: -10_000),
            size: TargetOverlayMetrics.panelSize
        )

        presenter.show(
            state: .confirmed(makePresentationValue()),
            outputName: "Fixture Output",
            frame: frame
        )
        defer { presenter.hide() }

        let windowFrame = TargetOverlayMetrics.windowFrame(containing: frame)
        #expect(panel.frame == NSRect(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y,
            width: windowFrame.size.width,
            height: windowFrame.size.height
        ))
        #expect(panel.isVisible)
        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)

        presenter.hide()
        #expect(!panel.isVisible)
    }

    @Test("Visual state mapping covers every presentation state")
    func visualStateMapping() {
        let value = makePresentationValue()
        let mutedValue = makePresentationValue(isMuted: true)

        let hiddenStates: [MediaTargetPresentationState] = [.hidden, .suspended, .routeLost]
        for state in hiddenStates {
            let visualState = TargetOverlayVisualState(presentationState: state)
            #expect(!visualState.isVisible)
            #expect(visualState.glyph == nil)
            #expect(visualState.level == nil)
        }

        let pendingCold = TargetOverlayVisualState(presentationState: .pendingCold(.up))
        #expect(pendingCold.isVisible)
        #expect(pendingCold.glyph == .speaker)
        #expect(pendingCold.level == nil)
        #expect(pendingCold.levelTreatment == .none)

        let pendingBaseline = TargetOverlayVisualState(
            presentationState: .pendingBaseline(.down, value)
        )
        #expect(pendingBaseline.glyph == .speakerMedium)
        #expect(pendingBaseline.level == 0.5)
        #expect(pendingBaseline.levelTreatment == .pending)

        let confirmed = TargetOverlayVisualState(presentationState: .confirmed(value))
        #expect(confirmed.glyph == .speakerMedium)
        #expect(confirmed.level == 0.5)
        #expect(confirmed.levelTreatment == .confirmed)

        for rail in [MediaTargetPresentationRail.minimum, .maximum] {
            let visualState = TargetOverlayVisualState(presentationState: .rail(rail, value))
            #expect(visualState.glyph == .speakerMedium)
            #expect(visualState.level == 0.5)
            #expect(visualState.levelTreatment == .confirmed)
        }

        let muted = TargetOverlayVisualState(presentationState: .muted(mutedValue))
        #expect(muted.glyph == .muted)
        #expect(muted.level == 0.5)
        #expect(muted.levelTreatment == .muted)

        let failedWithValue = TargetOverlayVisualState(presentationState: .failed(value))
        #expect(failedWithValue.glyph == .warning)
        #expect(failedWithValue.level == 0.5)
        #expect(failedWithValue.levelTreatment == .frozen)

        let failedWithoutValue = TargetOverlayVisualState(presentationState: .failed(nil))
        #expect(failedWithoutValue.glyph == .warning)
        #expect(failedWithoutValue.level == nil)
        #expect(failedWithoutValue.levelTreatment == .none)
    }

    @Test("Visual state bounds levels and percentage semantics")
    func visualStateBoundsLevels() {
        let belowMinimum = makePresentationValue(normalizedLevel: -0.25)
        let aboveMaximum = makePresentationValue(normalizedLevel: 1.25)

        let minimumVisualState = TargetOverlayVisualState(
            presentationState: .confirmed(belowMinimum)
        )
        let maximumVisualState = TargetOverlayVisualState(
            presentationState: .confirmed(aboveMaximum)
        )

        #expect(minimumVisualState.level == 0)
        #expect(minimumVisualState.glyph == .speaker)
        #expect(maximumVisualState.level == 1)
        #expect(maximumVisualState.glyph == .speakerHigh)

        #expect(TargetOverlayVisualState(
            presentationState: .confirmed(makePresentationValue(normalizedLevel: 0.2))
        ).glyph == .speakerLow)
        #expect(TargetOverlayVisualState(
            presentationState: .confirmed(makePresentationValue(normalizedLevel: 0.5))
        ).glyph == .speakerMedium)
    }

    @Test("Accessibility display changes refresh the presenter without ordering a panel")
    func accessibilityDisplayOptionsRefresh() {
        let notificationCenter = NotificationCenter()
        let optionsProvider = OverlayAccessibilityDisplayOptionsProviderStub(
            options: TargetOverlayAccessibilityDisplayOptions(
                reduceTransparency: false,
                increaseContrast: false
            )
        )
        let panel = TargetOverlayPanel()
        let presenter = TargetOverlayPanelPresenter(
            panel: panel,
            accessibilityDisplayOptionsProvider: optionsProvider,
            notificationCenter: notificationCenter
        )

        #expect(!panel.hasShadow)
        #expect(!panel.isAccessibilityElement())
        #expect(!panel.isVisible)
        if #available(macOS 26.0, *) {
            let glass = presenter.surfaceView as? NSGlassEffectView
            #expect(glass != nil)
            #expect(glass?.style == .regular)
            #expect(glass?.cornerRadius == CGFloat(TargetOverlayMetrics.cornerRadius))
            #expect(glass?.tintColor == nil)
            #expect(glass?.contentView === presenter.contentView)
            if #available(macOS 27.0, *) {
                #expect(glass?.effectIsInteractive == false)
            }
        }

        let initialSurfaceView = presenter.surfaceView
        optionsProvider.options = TargetOverlayAccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: true
        )
        notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(presenter.surfaceView === initialSurfaceView)
        #expect(presenter.contentView.rootView.surfaceStyle == .contentOnly)

        optionsProvider.options = TargetOverlayAccessibilityDisplayOptions(
            reduceTransparency: true,
            increaseContrast: true
        )
        notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        #expect(presenter.accessibilityDisplayOptions == optionsProvider.options)
        #expect(!panel.hasShadow)
        #expect(presenter.surfaceView === presenter.contentView)
        #expect(presenter.contentView.rootView.surfaceStyle == .opaque)
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
    private(set) var outputNames: [String] = []
    private(set) var frames: [OverlayRect] = []
    private(set) var hideCount = 0

    func show(state: MediaTargetPresentationState, outputName: String, frame: OverlayRect) {
        showStates.append(state)
        outputNames.append(outputName)
        frames.append(frame)
    }

    func hide() {
        hideCount += 1
    }
}

@MainActor
private final class OverlayAccessibilityDisplayOptionsProviderStub:
    TargetOverlayAccessibilityDisplayOptionsProviding
{
    var options: TargetOverlayAccessibilityDisplayOptions

    init(options: TargetOverlayAccessibilityDisplayOptions) {
        self.options = options
    }

    var accessibilityDisplayOptions: TargetOverlayAccessibilityDisplayOptions {
        options
    }
}

private func makePresentationValue(
    isMuted: Bool = false,
    normalizedLevel: Double = 0.5
) -> MediaTargetPresentationValue {
    MediaTargetPresentationValue(
        normalizedLevel: normalizedLevel,
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
