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

    func probe() async -> TransportReachability? {
        let requestedGeneration = generation
        let reachability: TransportReachability
        do {
            _ = try await target.readState()
            reachability = .reachable
        } catch .cancelled {
            reachability = .unknown
        } catch .authenticationRejected {
            reachability = .authenticationRejected
        } catch {
            reachability = .unreachable
        }

        guard generation == requestedGeneration else {
            return nil
        }
        return reachability
    }

    func execute(_ action: VolumeAction) async -> TransportReachability? {
        guard !Task.isCancelled else {
            return nil
        }
        let requestedGeneration = generation
        let reachability: TransportReachability?
        do {
            _ = try await executor.execute(action)
            reachability = .reachable
        } catch .cancelled {
            reachability = nil
        } catch .authenticationRejected {
            reachability = .authenticationRejected
        } catch {
            reachability = .unreachable
        }

        guard generation == requestedGeneration else {
            return nil
        }
        return reachability
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
