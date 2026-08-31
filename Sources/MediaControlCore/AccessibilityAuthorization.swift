public enum AccessibilityAuthorization: Sendable, Equatable {
    case notDetermined
    case requested
    case denied
    case granted
}

public enum AccessibilityDecision {
    public static func resolve(
        preflightGranted: Bool,
        hasRequestedAccess: Bool,
        requestedThisLaunch: Bool
    ) -> AccessibilityAuthorization {
        if preflightGranted {
            return .granted
        }
        if requestedThisLaunch {
            return .requested
        }
        return hasRequestedAccess ? .denied : .notDetermined
    }
}
