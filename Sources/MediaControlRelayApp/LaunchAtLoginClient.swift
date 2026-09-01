import Foundation
import ServiceManagement

enum LaunchAtLoginOperation: Equatable {
    case register
    case unregister
}

enum LaunchAtLoginState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notFound
        }
    }

    var isEnabled: Bool {
        self == .enabled
    }

    var title: LocalizedStringResource {
        switch self {
        case .notRegistered:
            return "Not enabled"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Approval required"
        case .notFound:
            return "Unavailable"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .notRegistered:
            return "Media Control Relay will not open automatically at login."
        case .enabled:
            return "Media Control Relay opens automatically when you log in."
        case .requiresApproval:
            return "Allow Media Control Relay in System Settings → General → Login Items to finish enabling it."
        case .notFound:
            return "macOS could not find this app as a Service Management login item."
        }
    }

    var systemImage: String {
        switch self {
        case .notRegistered:
            return "moon"
        case .enabled:
            return "checkmark.circle.fill"
        case .requiresApproval:
            return "exclamationmark.triangle"
        case .notFound:
            return "questionmark.circle"
        }
    }

    var recoveryActionAvailable: Bool {
        switch self {
        case .requiresApproval:
            return true
        case .notRegistered, .enabled, .notFound:
            return false
        }
    }
}

extension LaunchAtLoginOperation {
    var failureDetail: LocalizedStringResource {
        switch self {
        case .register:
            return "macOS could not enable launch at login. Try again or check Login Items settings."
        case .unregister:
            return "macOS could not disable launch at login. Try again."
        }
    }
}

@MainActor
struct LaunchAtLoginClient {
    let status: () -> LaunchAtLoginState
    let register: () throws -> Void
    let unregister: () throws -> Void
    let openSystemSettingsLoginItems: () -> Void

    static let live = LaunchAtLoginClient(
        status: {
            LaunchAtLoginState(serviceStatus: SMAppService.mainApp.status)
        },
        register: {
            try SMAppService.mainApp.register()
        },
        unregister: {
            try SMAppService.mainApp.unregister()
        },
        openSystemSettingsLoginItems: {
            SMAppService.openSystemSettingsLoginItems()
        }
    )
}
