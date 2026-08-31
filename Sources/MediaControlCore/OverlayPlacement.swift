import Foundation

public struct OverlayPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct OverlaySize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct OverlayRect: Equatable, Sendable {
    public let origin: OverlayPoint
    public let size: OverlaySize

    public init(origin: OverlayPoint, size: OverlaySize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(
            origin: OverlayPoint(x: x, y: y),
            size: OverlaySize(width: width, height: height)
        )
    }
}

public struct OverlayScreenDescriptor: Equatable, Sendable {
    public let stableIdentifier: String?
    public let name: String?
    public let frame: OverlayRect
    public let visibleFrame: OverlayRect
    public let backingScaleFactor: Double
    public let containsPointer: Bool
    public let isMain: Bool

    public init(
        stableIdentifier: String? = nil,
        name: String? = nil,
        frame: OverlayRect,
        visibleFrame: OverlayRect,
        backingScaleFactor: Double = 1,
        containsPointer: Bool = false,
        isMain: Bool = false
    ) {
        self.stableIdentifier = stableIdentifier
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.containsPointer = containsPointer
        self.isMain = isMain
    }
}

public enum OverlayPlacementReason: String, Equatable, Sendable {
    case matchedRouteDisplayStableIdentifier = "matched-route-display-stable-identifier"
    case matchedRouteDisplayName = "matched-route-display-name"
    case singleLiveScreen = "single-live-screen"
    case pointerContainingScreen = "pointer-containing-screen"
    case mainScreen = "main-screen"
    case firstScreen = "first-screen"
}

public struct OverlayScreenPlacement: Equatable, Sendable {
    public let screen: OverlayScreenDescriptor
    public let reason: OverlayPlacementReason

    public init(screen: OverlayScreenDescriptor, reason: OverlayPlacementReason) {
        self.screen = screen
        self.reason = reason
    }
}

public enum OverlayPlacementResolver {
    public static func resolve(
        activationRule: ActivationRule,
        routeSnapshot: RouteSnapshot,
        screens: [OverlayScreenDescriptor]
    ) -> OverlayScreenPlacement? {
        guard !screens.isEmpty else {
            return nil
        }

        let matchingDisplays = activationRule.requiresDisplay
            ? routeSnapshot.displays.filter { activationRule.matchesDisplayName($0.name) }
            : []
        if matchingDisplays.count == 1, let matchingDisplay = matchingDisplays.first {
            if let stableIdentifier = matchingDisplay.stableIdentifier {
                let matchingScreens = screens.filter {
                    $0.stableIdentifier == stableIdentifier
                }
                if matchingScreens.count == 1, let screen = matchingScreens.first {
                    return OverlayScreenPlacement(
                        screen: screen,
                        reason: .matchedRouteDisplayStableIdentifier
                    )
                }
            } else if let name = matchingDisplay.name {
                let matchingScreens = screens.filter {
                    namesMatch($0.name, name)
                }
                if matchingScreens.count == 1, let screen = matchingScreens.first {
                    return OverlayScreenPlacement(
                        screen: screen,
                        reason: .matchedRouteDisplayName
                    )
                }
            }
        }

        if screens.count == 1, let screen = screens.first {
            return OverlayScreenPlacement(screen: screen, reason: .singleLiveScreen)
        }
        if let screen = screens.first(where: \.containsPointer) {
            return OverlayScreenPlacement(screen: screen, reason: .pointerContainingScreen)
        }
        if let screen = screens.first(where: \.isMain) {
            return OverlayScreenPlacement(screen: screen, reason: .mainScreen)
        }
        guard let screen = screens.sorted(by: isOrderedBefore).first else {
            return nil
        }
        return OverlayScreenPlacement(screen: screen, reason: .firstScreen)
    }

    private static func isOrderedBefore(
        _ lhs: OverlayScreenDescriptor,
        _ rhs: OverlayScreenDescriptor
    ) -> Bool {
        if lhs.frame.origin.x != rhs.frame.origin.x {
            return lhs.frame.origin.x < rhs.frame.origin.x
        }
        if lhs.frame.origin.y != rhs.frame.origin.y {
            return lhs.frame.origin.y < rhs.frame.origin.y
        }
        if lhs.stableIdentifier != rhs.stableIdentifier {
            return (lhs.stableIdentifier ?? "") < (rhs.stableIdentifier ?? "")
        }
        return (lhs.name ?? "") < (rhs.name ?? "")
    }

    private static func namesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs = normalizedName(lhs), let rhs = normalizedName(rhs) else {
            return false
        }
        return lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) ==
            rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

public enum OverlayPanelGeometry {
    public static func topTrailingRect(
        panelSize: OverlaySize,
        on screen: OverlayScreenDescriptor,
        topInset: Double,
        trailingInset: Double
    ) -> OverlayRect {
        let visibleFrame = normalized(screen.visibleFrame)
        let scale = normalizedScale(screen.backingScaleFactor)
        let width = alignedDimension(panelSize.width, limit: visibleFrame.size.width, scale: scale)
        let height = alignedDimension(panelSize.height, limit: visibleFrame.size.height, scale: scale)

        let maximumX = visibleFrame.origin.x + visibleFrame.size.width - width
        let maximumY = visibleFrame.origin.y + visibleFrame.size.height - height
        let desiredX = maximumX - max(0, finite(trailingInset, fallback: 0))
        let desiredY = maximumY - max(0, finite(topInset, fallback: 0))

        let x = alignedCoordinate(
            clamped(desiredX, minimum: visibleFrame.origin.x, maximum: maximumX),
            minimum: visibleFrame.origin.x,
            maximum: maximumX,
            scale: scale
        )
        let y = alignedCoordinate(
            clamped(desiredY, minimum: visibleFrame.origin.y, maximum: maximumY),
            minimum: visibleFrame.origin.y,
            maximum: maximumY,
            scale: scale
        )

        return OverlayRect(x: x, y: y, width: width, height: height)
    }

    private static func normalized(_ rect: OverlayRect) -> OverlayRect {
        OverlayRect(
            x: finite(rect.origin.x, fallback: 0),
            y: finite(rect.origin.y, fallback: 0),
            width: max(0, finite(rect.size.width, fallback: 0)),
            height: max(0, finite(rect.size.height, fallback: 0))
        )
    }

    private static func normalizedScale(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 1
        }
        return value
    }

    private static func alignedDimension(_ value: Double, limit: Double, scale: Double) -> Double {
        let bounded = min(max(0, finite(value, fallback: 0)), limit)
        return min((bounded * scale).rounded() / scale, limit)
    }

    private static func alignedCoordinate(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        scale: Double
    ) -> Double {
        let rounded = (value * scale).rounded() / scale
        if rounded >= minimum && rounded <= maximum {
            return rounded
        }
        if rounded < minimum {
            let alignedMinimum = (minimum * scale).rounded(.up) / scale
            return alignedMinimum <= maximum ? alignedMinimum : minimum
        }
        let alignedMaximum = (maximum * scale).rounded(.down) / scale
        return alignedMaximum >= minimum ? alignedMaximum : maximum
    }

    private static func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}
