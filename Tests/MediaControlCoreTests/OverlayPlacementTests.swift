import Testing
@testable import MediaControlCore

@Suite("Overlay placement")
struct OverlayPlacementTests {
    @Test("Display helper preserves activation display matching")
    func displayMatchingParity() {
        let rule = ActivationRule(audioOutputMatch: "Samsung", displayMatch: "Sámsung")
        let snapshot = ActivationSnapshot(
            defaultAudioOutputName: "Samsung HDMI",
            displayNames: ["samsung television"]
        )

        #expect(rule.matchesDisplayName("samsung television"))
        #expect(!rule.matchesDisplayName("Other display"))
        #expect(rule.matches(snapshot))
    }

    @Test("A unique route display maps through its stable identifier")
    func stableIdentifierMatch() {
        let target = screen(identifier: "live-target", name: "Living Room")
        let placement = OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: [
                DisplaySnapshot(name: "Living Room TV", stableIdentifier: "live-target"),
            ]),
            screens: [screen(identifier: "other", name: "Office"), target]
        )

        #expect(placement == OverlayScreenPlacement(
            screen: target,
            reason: .matchedRouteDisplayStableIdentifier
        ))
    }

    @Test("A route display without an identifier can map a unique live name")
    func uniqueLiveNameMatch() {
        let target = screen(name: "Living Room TV")
        let placement = OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: [DisplaySnapshot(name: "Living Room TV")]),
            screens: [target, screen(name: "Office")]
        )

        #expect(placement == OverlayScreenPlacement(screen: target, reason: .matchedRouteDisplayName))
    }

    @Test("Audio-only routes use the primary fallback")
    func audioOnlyPrimaryFallback() {
        let pointer = screen(name: "Pointer", containsPointer: true)
        let placement = OverlayPlacementResolver.resolve(
            activationRule: ActivationRule(audioOutputMatch: "Living Room", requiresDisplay: false),
            routeSnapshot: route(displays: []),
            screens: [screen(name: "Main", isMain: true), pointer]
        )

        #expect(placement == OverlayScreenPlacement(
            screen: pointer,
            reason: .pointerContainingScreen
        ))
    }

    @Test("Ambiguous identical route display names use fallback")
    func ambiguousIdenticalNamesFallback() {
        let pointer = screen(name: "Pointer", containsPointer: true)
        let placement = OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: [
                DisplaySnapshot(name: "Living Room TV", stableIdentifier: "one"),
                DisplaySnapshot(name: "Living Room TV", stableIdentifier: "two"),
            ]),
            screens: [pointer, screen(identifier: "one", name: "Living Room TV")]
        )

        #expect(placement == OverlayScreenPlacement(
            screen: pointer,
            reason: .pointerContainingScreen
        ))
    }

    @Test("Detached matched display uses fallback")
    func detachedDisplayFallback() {
        let main = screen(name: "Main", isMain: true)
        let placement = OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: [
                DisplaySnapshot(name: "Living Room TV", stableIdentifier: "detached"),
            ]),
            screens: [screen(name: "Other"), main]
        )

        #expect(placement == OverlayScreenPlacement(screen: main, reason: .mainScreen))
    }

    @Test("Single screen wins before pointer and main fallback")
    func singleScreenFallback() {
        let onlyScreen = screen(name: "Only")
        let placement = OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: []),
            screens: [onlyScreen]
        )

        #expect(placement == OverlayScreenPlacement(screen: onlyScreen, reason: .singleLiveScreen))
    }

    @Test("Fallback order is pointer then main then first")
    func fallbackOrder() {
        let pointer = screen(name: "Pointer", containsPointer: true)
        let main = screen(name: "Main", isMain: true)
        let first = screen(name: "First")

        #expect(OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: []),
            screens: [first, main, pointer]
        )?.reason == .pointerContainingScreen)
        #expect(OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: []),
            screens: [first, main]
        )?.reason == .mainScreen)
        #expect(OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: []),
            screens: [first, screen(name: "Second")]
        )?.reason == .firstScreen)
    }

    @Test("No live screens produces no placement")
    func noScreens() {
        #expect(OverlayPlacementResolver.resolve(
            activationRule: rule(),
            routeSnapshot: route(displays: []),
            screens: []
        ) == nil)
    }

    @Test("Geometry centers full frame and respects a bottom Dock visible frame")
    func bottomDockGeometry() {
        let screen = screen(
            frame: OverlayRect(x: -1440, y: 0, width: 1440, height: 900),
            visibleFrame: OverlayRect(x: -1440, y: 84, width: 1440, height: 816)
        )

        let rect = OverlayPanelGeometry.bottomCenterRect(
            panelSize: OverlaySize(width: 300, height: 120),
            on: screen,
            bottomInset: 24
        )

        #expect(rect == OverlayRect(x: -870, y: 108, width: 300, height: 120))
    }

    @Test("Geometry clamps against a side Dock visible frame")
    func sideDockGeometry() {
        let screen = screen(
            frame: OverlayRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: OverlayRect(x: 96, y: 0, width: 1344, height: 900)
        )

        let rect = OverlayPanelGeometry.bottomCenterRect(
            panelSize: OverlaySize(width: 1400, height: 100),
            on: screen,
            bottomInset: 20
        )

        #expect(rect == OverlayRect(x: 96, y: 20, width: 1344, height: 100))
    }

    @Test("Oversized panels are fully contained by the visible frame")
    func oversizedPanelGeometry() {
        let screen = screen(
            frame: OverlayRect(x: -500, y: -300, width: 500, height: 300),
            visibleFrame: OverlayRect(x: -480, y: -260, width: 440, height: 240)
        )

        let rect = OverlayPanelGeometry.bottomCenterRect(
            panelSize: OverlaySize(width: 700, height: 500),
            on: screen,
            bottomInset: 30
        )

        #expect(rect == OverlayRect(x: -480, y: -260, width: 440, height: 240))
    }

    @Test("Geometry aligns origin and size to fractional backing scale")
    func fractionalScaleGeometry() {
        let screen = screen(
            frame: OverlayRect(x: 0, y: 0, width: 401, height: 700),
            visibleFrame: OverlayRect(x: 0, y: 0, width: 401, height: 700),
            backingScaleFactor: 1.25
        )

        let rect = OverlayPanelGeometry.bottomCenterRect(
            panelSize: OverlaySize(width: 200, height: 99),
            on: screen,
            bottomInset: 17
        )

        #expect(rect == OverlayRect(x: 100.8, y: 16.8, width: 200, height: 99.2))
    }

    private func rule() -> ActivationRule {
        ActivationRule(audioOutputMatch: "Living Room", displayMatch: "Living Room TV")
    }

    private func route(displays: [DisplaySnapshot]) -> RouteSnapshot {
        RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "Living Room HDMI",
                transportKind: .display
            ),
            displays: displays
        )
    }

    private func screen(
        identifier: String? = nil,
        name: String? = nil,
        frame: OverlayRect = OverlayRect(x: 0, y: 0, width: 100, height: 100),
        visibleFrame: OverlayRect = OverlayRect(x: 0, y: 0, width: 100, height: 100),
        backingScaleFactor: Double = 1,
        containsPointer: Bool = false,
        isMain: Bool = false
    ) -> OverlayScreenDescriptor {
        OverlayScreenDescriptor(
            stableIdentifier: identifier,
            name: name,
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: backingScaleFactor,
            containsPointer: containsPointer,
            isMain: isMain
        )
    }
}
