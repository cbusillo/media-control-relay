import Foundation

public enum TransportReachability: Equatable, Sendable {
    case unknown
    case reachable
    case unreachable
}

public enum BridgeState: Equatable, Sendable {
    case unconfigured
    case unsupported
    case needsPermission
    case dormant
    case offline
    case active
}

public struct BridgeStateInputs: Equatable, Sendable {
    public var credentialsConfigured: Bool
    public var deviceSupported: Bool
    public var inputMonitoringGranted: Bool
    public var activationMatches: Bool
    public var transportReachability: TransportReachability

    public init(
        credentialsConfigured: Bool,
        deviceSupported: Bool,
        inputMonitoringGranted: Bool,
        activationMatches: Bool,
        transportReachability: TransportReachability
    ) {
        self.credentialsConfigured = credentialsConfigured
        self.deviceSupported = deviceSupported
        self.inputMonitoringGranted = inputMonitoringGranted
        self.activationMatches = activationMatches
        self.transportReachability = transportReachability
    }
}

public enum BridgeStateResolver {
    public static func resolve(_ inputs: BridgeStateInputs) -> BridgeState {
        guard inputs.credentialsConfigured else {
            return .unconfigured
        }
        guard inputs.deviceSupported else {
            return .unsupported
        }
        guard inputs.inputMonitoringGranted else {
            return .needsPermission
        }
        guard inputs.activationMatches else {
            return .dormant
        }
        guard inputs.transportReachability == .reachable else {
            return .offline
        }
        return .active
    }
}
