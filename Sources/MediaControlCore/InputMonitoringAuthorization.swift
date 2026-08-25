public enum InputMonitoringAuthorization: Sendable, Equatable {
    case notDetermined
    case requested
    case denied
    case granted
}

public enum InputMonitoringDecision {
    public static func resolve(
        preflightGranted: Bool,
        hasRequestedAccess: Bool,
        requestedThisLaunch: Bool
    ) -> InputMonitoringAuthorization {
        if preflightGranted {
            return .granted
        }
        if requestedThisLaunch {
            return .requested
        }
        return hasRequestedAccess ? .denied : .notDetermined
    }
}
