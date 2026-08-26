import Dispatch
import Network

enum NetworkPathStatus: String, Equatable, Sendable {
    case unknown
    case available
    case unavailable
    case localNetworkDenied = "local-network-denied"
}

enum NetworkInterfaceKind: String, CaseIterable, Hashable, Sendable {
    case wired
    case wifi
    case cellular
    case loopback
    case other
}

struct NetworkPathSnapshot: Equatable, Sendable {
    let status: NetworkPathStatus
    let interfaceKinds: Set<NetworkInterfaceKind>
    let supportsIPv4: Bool

    static let unknown = NetworkPathSnapshot(
        status: .unknown,
        interfaceKinds: [],
        supportsIPv4: false
    )

    init(
        status: NetworkPathStatus,
        interfaceKinds: Set<NetworkInterfaceKind> = [],
        supportsIPv4: Bool = false
    ) {
        self.status = status
        self.interfaceKinds = interfaceKinds
        self.supportsIPv4 = supportsIPv4
    }

    init(path: NWPath) {
        if path.status == .unsatisfied,
           path.unsatisfiedReason == .localNetworkDenied {
            status = .localNetworkDenied
        } else if path.status == .satisfied, path.supportsIPv4 {
            status = .available
        } else {
            status = .unavailable
        }

        interfaceKinds = Set(NetworkInterfaceKind.allCases.filter { kind in
            switch kind {
            case .wired:
                path.usesInterfaceType(.wiredEthernet)
            case .wifi:
                path.usesInterfaceType(.wifi)
            case .cellular:
                path.usesInterfaceType(.cellular)
            case .loopback:
                path.usesInterfaceType(.loopback)
            case .other:
                path.usesInterfaceType(.other)
            }
        })
        supportsIPv4 = path.supportsIPv4
    }
}

@MainActor
protocol NetworkPathObserving: AnyObject {
    var onSnapshot: ((NetworkPathSnapshot) -> Void)? { get set }

    func start()
    func stop()
    @discardableResult
    func refresh() -> NetworkPathSnapshot?
}

@MainActor
final class SystemNetworkPathObserver: NetworkPathObserving {
    var onSnapshot: ((NetworkPathSnapshot) -> Void)?

    private let monitor: NWPathMonitor
    private var lastSnapshot = NetworkPathSnapshot.unknown
    private var started = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated {
                self?.publish(NetworkPathSnapshot(path: path))
            }
        }
        monitor.start(queue: .main)
    }

    func stop() {
        guard started else {
            return
        }
        started = false
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    @discardableResult
    func refresh() -> NetworkPathSnapshot? {
        guard started else {
            return nil
        }
        let snapshot = NetworkPathSnapshot(path: monitor.currentPath)
        publish(snapshot)
        return snapshot
    }

    private func publish(_ snapshot: NetworkPathSnapshot) {
        guard snapshot != lastSnapshot else {
            return
        }
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}

@MainActor
final class InactiveNetworkPathObserver: NetworkPathObserving {
    var onSnapshot: ((NetworkPathSnapshot) -> Void)?

    func start() {}
    func stop() {}
    func refresh() -> NetworkPathSnapshot? { nil }
}
