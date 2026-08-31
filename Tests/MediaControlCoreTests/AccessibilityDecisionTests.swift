import Testing
@testable import MediaControlCore

@Suite("Accessibility decision")
struct AccessibilityDecisionTests {
    @Test("Granted preflight wins over request history")
    func grantedPreflightWins() {
        #expect(
            AccessibilityDecision.resolve(
                preflightGranted: true,
                hasRequestedAccess: true,
                requestedThisLaunch: true
            ) == .granted
        )
    }

    @Test("Current launch request remains pending")
    func currentRequestIsPending() {
        #expect(
            AccessibilityDecision.resolve(
                preflightGranted: false,
                hasRequestedAccess: true,
                requestedThisLaunch: true
            ) == .requested
        )
    }

    @Test("Prior request resolves as denied")
    func priorRequestIsDenied() {
        #expect(
            AccessibilityDecision.resolve(
                preflightGranted: false,
                hasRequestedAccess: true,
                requestedThisLaunch: false
            ) == .denied
        )
    }

    @Test("No request remains undetermined")
    func noRequestIsUndetermined() {
        #expect(
            AccessibilityDecision.resolve(
                preflightGranted: false,
                hasRequestedAccess: false,
                requestedThisLaunch: false
            ) == .notDetermined
        )
    }
}
