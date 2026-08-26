import Foundation

public enum TransportReachability: Equatable, Sendable {
    case unknown
    case reachable
    case unreachable
    case permissionDenied
}

public enum RelayState: Equatable, Sendable {
    case unconfigured
    case unsupported
    case needsPermission
    case needsLocalNetworkPermission
    case dormant
    case checkingTarget
    case offline
    case active
}

public struct RelayStateInputs: Equatable, Sendable {
    public var targetConfigured: Bool
    public var deviceSupported: Bool
    public var inputMonitoringGranted: Bool
    public var activationMatches: Bool
    public var transportReachability: TransportReachability

    public init(
        targetConfigured: Bool,
        deviceSupported: Bool,
        inputMonitoringGranted: Bool,
        activationMatches: Bool,
        transportReachability: TransportReachability
    ) {
        self.targetConfigured = targetConfigured
        self.deviceSupported = deviceSupported
        self.inputMonitoringGranted = inputMonitoringGranted
        self.activationMatches = activationMatches
        self.transportReachability = transportReachability
    }
}

public enum RelayStateResolver {
    public static func resolve(_ inputs: RelayStateInputs) -> RelayState {
        guard inputs.targetConfigured else {
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
        switch inputs.transportReachability {
        case .reachable:
            return .active
        case .unknown:
            return .checkingTarget
        case .unreachable:
            return .offline
        case .permissionDenied:
            return .needsLocalNetworkPermission
        }
    }
}
