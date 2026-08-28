import Foundation
import MediaControlCore
import UPnPMediaTarget

enum MediaTargetSessionInvalidation: Equatable, Sendable {
    case authorizationChanged
    case routeContextChanged
    case networkContextChanged
    case lifecycleChanged
    case sessionReplaced
}

actor MediaTargetSession {
    typealias ResolutionInvalidator = @Sendable (MediaTargetSessionInvalidation) async -> Void

    private let target: any MediaVolumeTarget
    private let executor: MediaTargetCommandExecutor
    private let invalidateResolution: ResolutionInvalidator
    private var generation: UInt64 = 0
    private var latestInvalidationRequestID: UInt64 = 0

    init(
        target: any MediaVolumeTarget,
        invalidateResolution: @escaping ResolutionInvalidator
    ) {
        self.target = target
        self.executor = MediaTargetCommandExecutor(target: target)
        self.invalidateResolution = invalidateResolution
    }

    func probe() async -> MediaTargetSessionOutcome? {
        guard !Task.isCancelled else {
            return nil
        }
        generation &+= 1
        let requestedGeneration = generation
        let reachability: TransportReachability
        let confirmedState: MediaTargetVolumeState?
        do {
            confirmedState = try await target.readState()
            reachability = .reachable
        } catch .cancelled {
            return nil
        } catch .authenticationRejected {
            reachability = .authenticationRejected
            confirmedState = nil
        } catch .localNetworkDenied {
            reachability = .localNetworkDenied
            confirmedState = nil
        } catch {
            reachability = .unreachable
            confirmedState = nil
        }

        guard !Task.isCancelled, generation == requestedGeneration else {
            return nil
        }
        return MediaTargetSessionOutcome(
            reachability: reachability,
            confirmedState: confirmedState,
            generation: requestedGeneration
        )
    }

    func execute(_ action: VolumeAction) async -> MediaTargetSessionOutcome? {
        guard !Task.isCancelled else {
            return nil
        }
        generation &+= 1
        let requestedGeneration = generation
        let reachability: TransportReachability
        let confirmedState: MediaTargetVolumeState?
        do {
            confirmedState = try await executor.execute(action)
            reachability = .reachable
        } catch .cancelled {
            return nil
        } catch .authenticationRejected {
            reachability = .authenticationRejected
            confirmedState = nil
        } catch .localNetworkDenied {
            reachability = .localNetworkDenied
            confirmedState = nil
        } catch {
            reachability = .unreachable
            confirmedState = nil
        }

        guard !Task.isCancelled, generation == requestedGeneration else {
            return nil
        }
        return MediaTargetSessionOutcome(
            reachability: reachability,
            confirmedState: confirmedState,
            generation: requestedGeneration
        )
    }

    func invalidate(
        _ reason: MediaTargetSessionInvalidation,
        requestID: UInt64? = nil
    ) async {
        if let requestID {
            guard requestID >= latestInvalidationRequestID else {
                return
            }
            latestInvalidationRequestID = requestID
        }
        generation &+= 1
        await invalidateResolution(reason)
    }
}

enum MediaTargetSessionFactory {
    static func make(
        configuration: RelayConfiguration?
    ) -> MediaTargetSession? {
        guard configuration?.target.kind == .upnpMediaRenderer,
              let stableIdentifier = configuration?.target.stableIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !stableIdentifier.isEmpty else {
            return nil
        }

        let identity = MediaTargetIdentity(stableIdentifier: stableIdentifier)
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: UPnPMediaTargetIPv4SSDPSearcher(),
            descriptorFetcher: UPnPMediaTargetURLSessionDescriptorFetcher()
        )
        let target = UPnPMediaVolumeTarget(
            identity: identity,
            resolver: resolver
        )
        return MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                switch reason {
                case .authorizationChanged:
                    return
                case .routeContextChanged:
                    await resolver.invalidate(for: .interfaceChanged)
                case .networkContextChanged:
                    await resolver.invalidate(for: .interfaceChanged)
                case .lifecycleChanged:
                    await resolver.invalidate(for: .lifecycleChanged)
                case .sessionReplaced:
                    await resolver.invalidate(for: .lifecycleChanged)
                }
            }
        )
    }
}
