import Testing
@testable import VolumeBridgeCore

@Suite("Bridge state resolution")
struct BridgeStateTests {
    @Test("Every public state is reachable")
    func everyStateIsReachable() {
        #expect(resolve(credentials: false) == .unconfigured)
        #expect(resolve(supported: false) == .unsupported)
        #expect(resolve(permission: false) == .needsPermission)
        #expect(resolve(matches: false) == .dormant)
        #expect(resolve(reachability: .unreachable) == .offline)
        #expect(resolve(reachability: .unknown) == .offline)
        #expect(resolve(reachability: .reachable) == .active)
    }

    @Test("Earlier recovery conditions take precedence")
    func precedence() {
        let inputs = BridgeStateInputs(
            credentialsConfigured: false,
            deviceSupported: false,
            inputMonitoringGranted: false,
            activationMatches: false,
            transportReachability: .unreachable
        )
        #expect(BridgeStateResolver.resolve(inputs) == .unconfigured)
    }

    private func resolve(
        credentials: Bool = true,
        supported: Bool = true,
        permission: Bool = true,
        matches: Bool = true,
        reachability: TransportReachability = .reachable
    ) -> BridgeState {
        BridgeStateResolver.resolve(
            BridgeStateInputs(
                credentialsConfigured: credentials,
                deviceSupported: supported,
                inputMonitoringGranted: permission,
                activationMatches: matches,
                transportReachability: reachability
            )
        )
    }
}
