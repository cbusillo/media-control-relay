import Foundation
import MediaControlCore

public enum UPnPMediaTargetResolverInvalidationSignal: Sendable {
    case interfaceChanged
    case lifecycleChanged
}

public actor UPnPMediaTargetResolver {
    private struct CachedDescriptor: Sendable {
        let generation: UInt64
        let descriptor: UPnPMediaTargetDescriptor
    }

    private struct ResolutionWaiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    public let identity: MediaTargetIdentity

    private let searcher: any UPnPMediaTargetSSDPSearching
    private let descriptorFetcher: any UPnPMediaTargetDescriptorFetching
    private let searchBounds: UPnPMediaTargetSSDPSearchBounds
    private var generation: UInt64 = 0
    private var cachedDescriptor: CachedDescriptor?
    private var resolutionActive = false
    private var resolutionWaiters: [ResolutionWaiter] = []
    private var nextResolutionWaiterID: UInt64 = 0

    public init(
        identity: MediaTargetIdentity,
        searcher: any UPnPMediaTargetSSDPSearching,
        descriptorFetcher: any UPnPMediaTargetDescriptorFetching,
        searchBounds: UPnPMediaTargetSSDPSearchBounds = .default
    ) {
        self.identity = identity
        self.searcher = searcher
        self.descriptorFetcher = descriptorFetcher
        self.searchBounds = searchBounds
    }

    public var currentGeneration: UInt64 {
        generation
    }

    var pendingResolutionCount: Int {
        resolutionWaiters.count
    }

    public func resolve() async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        guard await acquireResolution() else {
            throw .cancelled
        }
        defer { releaseResolution() }
        guard !Task.isCancelled else {
            throw .cancelled
        }

        while true {
            let requestedGeneration = generation
            if let cachedDescriptor,
               cachedDescriptor.generation == requestedGeneration {
                return cachedDescriptor.descriptor
            }

            let candidates = try await searcher.search(bounds: searchBounds)
            guard generation == requestedGeneration else {
                continue
            }
            var attemptedLocations = Set<URL>()
            var timedOutLocationCount = 0
            var capabilityError: UPnPMediaTargetError?
            for candidate in candidates.prefix(searchBounds.maximumCandidateCount) {
                guard generation == requestedGeneration else {
                    break
                }
                guard candidate.identity == identity,
                      attemptedLocations.insert(candidate.location).inserted else {
                    continue
                }

                let descriptor: UPnPMediaTargetDescriptor
                do {
                    descriptor = try await descriptorFetcher.fetch(location: candidate.location)
                } catch UPnPMediaTargetError.cancelled {
                    throw .cancelled
                } catch UPnPMediaTargetError.timeout {
                    timedOutLocationCount += 1
                    continue
                } catch let error {
                    switch error {
                    case .missingRenderingControlService,
                         .missingRenderingControlControlURL,
                         .missingRenderingControlSCPDURL,
                         .missingVolumeCapability,
                         .invalidVolumeCapability:
                        capabilityError = capabilityError ?? error
                        continue
                    default:
                        continue
                    }
                }

                guard descriptor.identity == identity else {
                    continue
                }
                guard generation == requestedGeneration else {
                    break
                }

                cachedDescriptor = CachedDescriptor(
                    generation: requestedGeneration,
                    descriptor: descriptor
                )
                return descriptor
            }

            guard generation == requestedGeneration else {
                continue
            }
            if !attemptedLocations.isEmpty,
               timedOutLocationCount == attemptedLocations.count {
                throw .timeout
            }
            if let capabilityError {
                throw capabilityError
            }
            throw .discoveryUnavailable
        }
    }

    public func invalidate() {
        generation &+= 1
        cachedDescriptor = nil
    }

    public func invalidate(for signal: UPnPMediaTargetResolverInvalidationSignal) {
        _ = signal
        invalidate()
    }

    private func acquireResolution() async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        if !resolutionActive {
            resolutionActive = true
            return true
        }

        let waiterID = nextResolutionWaiterID
        nextResolutionWaiterID &+= 1
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    resolutionWaiters.append(
                        ResolutionWaiter(
                            id: waiterID,
                            continuation: continuation
                        )
                    )
                }
            }
        }, onCancel: {
            Task {
                await self.cancelResolutionWaiter(waiterID)
            }
        })
    }

    private func releaseResolution() {
        if resolutionWaiters.isEmpty {
            resolutionActive = false
            return
        }
        let waiter = resolutionWaiters.removeFirst()
        waiter.continuation.resume(returning: true)
    }

    private func cancelResolutionWaiter(_ waiterID: UInt64) {
        guard let index = resolutionWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        let waiter = resolutionWaiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
