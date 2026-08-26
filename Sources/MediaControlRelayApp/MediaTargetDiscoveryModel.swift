import Observation
import UPnPMediaTarget

struct MediaTargetDiscoveryChoice: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
}

enum MediaTargetDiscoveryState: Equatable {
    case idle
    case scanning
    case results([MediaTargetDiscoveryChoice])
    case empty
    case failed
    case routeUnavailable([MediaTargetDiscoveryChoice])
}

@MainActor
@Observable
final class MediaTargetDiscoveryModel {
    private(set) var state: MediaTargetDiscoveryState = .idle

    private let scan: @Sendable () async throws -> [UPnPMediaTargetDiscoveryCandidate]
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        scan: @escaping @Sendable () async throws -> [UPnPMediaTargetDiscoveryCandidate] = {
            try await UPnPMediaTargetDiscoveryScan().scan()
        }
    ) {
        self.scan = scan
    }

    func startScan() {
        cancelScan(resetState: false)
        generation &+= 1
        let requestedGeneration = generation
        state = .scanning
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let candidates = try await scan()
                guard !Task.isCancelled, generation == requestedGeneration else {
                    return
                }
                let choices = candidates.map {
                    MediaTargetDiscoveryChoice(
                        id: $0.identity.stableIdentifier,
                        label: "Media Renderer \($0.ordinal)"
                    )
                }
                state = choices.isEmpty ? .empty : .results(choices)
            } catch {
                guard !Task.isCancelled, generation == requestedGeneration else {
                    return
                }
                state = .failed
            }
            task = nil
        }
    }

    func cancelScan(resetState: Bool = true) {
        generation &+= 1
        task?.cancel()
        task = nil
        if resetState {
            state = .idle
        }
    }

    func reportRouteUnavailable() {
        let choices: [MediaTargetDiscoveryChoice] = switch state {
        case let .results(choices), let .routeUnavailable(choices): choices
        default: []
        }
        cancelScan(resetState: false)
        state = .routeUnavailable(choices)
    }

    func reportRouteAvailable() {
        guard case let .routeUnavailable(choices) = state else {
            return
        }
        state = choices.isEmpty ? .empty : .results(choices)
    }
}
