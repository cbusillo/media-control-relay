import Testing
@testable import MediaControlCore

@Suite("Relay state resolution")
struct RelayStateTests {
    @Test("Every public state is reachable")
    func everyStateIsReachable() {
        #expect(resolve(targetConfigured: false) == .unconfigured)
        #expect(resolve(supported: false) == .unsupported)
        #expect(resolve(permission: false) == .needsPermission)
        #expect(resolve(matches: false) == .dormant)
        #expect(resolve(reachability: .localNetworkDenied) == .needsLocalNetworkPermission)
        #expect(resolve(reachability: .authenticationRejected) == .targetAuthenticationRejected)
        #expect(resolve(reachability: .unknown) == .checkingTarget)
        #expect(resolve(reachability: .unreachable) == .offline)
        #expect(resolve(reachability: .reachable) == .active)
    }

    @Test("Earlier recovery conditions take precedence")
    func precedence() {
        let inputs = RelayStateInputs(
            targetConfigured: false,
            deviceSupported: false,
            inputMonitoringGranted: false,
            activationMatches: false,
            transportReachability: .unreachable
        )
        #expect(RelayStateResolver.resolve(inputs) == .unconfigured)
    }

    private func resolve(
        targetConfigured: Bool = true,
        supported: Bool = true,
        permission: Bool = true,
        matches: Bool = true,
        reachability: TransportReachability = .reachable
    ) -> RelayState {
        RelayStateResolver.resolve(
            RelayStateInputs(
                targetConfigured: targetConfigured,
                deviceSupported: supported,
                inputMonitoringGranted: permission,
                activationMatches: matches,
                transportReachability: reachability
            )
        )
    }
}
