import Testing
@testable import MediaControlCore

@Suite("Input Monitoring authorization")
struct InputMonitoringDecisionTests {
    @Test("Granted preflight always wins")
    func granted() {
        #expect(InputMonitoringDecision.resolve(
            preflightGranted: true,
            hasRequestedAccess: false,
            requestedThisLaunch: false
        ) == .granted)
        #expect(InputMonitoringDecision.resolve(
            preflightGranted: true,
            hasRequestedAccess: true,
            requestedThisLaunch: true
        ) == .granted)
    }

    @Test("A missing grant is initially undetermined")
    func notDetermined() {
        #expect(InputMonitoringDecision.resolve(
            preflightGranted: false,
            hasRequestedAccess: false,
            requestedThisLaunch: false
        ) == .notDetermined)
    }

    @Test("A request remains pending during the launch that made it")
    func requested() {
        #expect(InputMonitoringDecision.resolve(
            preflightGranted: false,
            hasRequestedAccess: true,
            requestedThisLaunch: true
        ) == .requested)
    }

    @Test("A missing grant after a request is denied")
    func denied() {
        #expect(InputMonitoringDecision.resolve(
            preflightGranted: false,
            hasRequestedAccess: true,
            requestedThisLaunch: false
        ) == .denied)
    }
}
