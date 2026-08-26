import Foundation
import MediaControlCore

public struct UPnPMediaTargetDiscoveryCandidate: Equatable, Sendable {
    public let identity: MediaTargetIdentity
    public let ordinal: Int

    public init(identity: MediaTargetIdentity, ordinal: Int) {
        self.identity = identity
        self.ordinal = ordinal
    }
}

public protocol UPnPMediaTargetDiscoveryScanning: Sendable {
    func scan() async throws(UPnPMediaTargetError) -> [UPnPMediaTargetDiscoveryCandidate]
}

public struct UPnPMediaTargetDiscoveryScan: UPnPMediaTargetDiscoveryScanning, Sendable {
    private let searcher: any UPnPMediaTargetSSDPSearching
    private let descriptorFetcher: any UPnPMediaTargetDescriptorFetching
    private let bounds: UPnPMediaTargetSSDPSearchBounds

    public init(
        searcher: any UPnPMediaTargetSSDPSearching = UPnPMediaTargetIPv4SSDPSearcher(),
        descriptorFetcher: any UPnPMediaTargetDescriptorFetching = UPnPMediaTargetURLSessionDescriptorFetcher(),
        bounds: UPnPMediaTargetSSDPSearchBounds = .default
    ) {
        self.searcher = searcher
        self.descriptorFetcher = descriptorFetcher
        self.bounds = bounds
    }

    public func scan() async throws(UPnPMediaTargetError) -> [UPnPMediaTargetDiscoveryCandidate] {
        let responses: [UPnPMediaTargetSSDPResponse]
        do {
            responses = try await searcher.search(bounds: bounds)
        } catch UPnPMediaTargetError.timeout {
            return []
        }
        var confirmed = Set<MediaTargetIdentity>()
        var attemptedLocations = Set<URL>()

        for response in responses.prefix(bounds.maximumCandidateCount) {
            guard !Task.isCancelled else {
                throw .cancelled
            }
            guard attemptedLocations.insert(response.location).inserted else {
                continue
            }
            do {
                let descriptor = try await descriptorFetcher.fetch(location: response.location)
                guard descriptor.identity == response.identity else {
                    continue
                }
                confirmed.insert(descriptor.identity)
            } catch UPnPMediaTargetError.cancelled {
                throw .cancelled
            } catch {
                continue
            }
        }

        return confirmed
            .sorted { $0.stableIdentifier < $1.stableIdentifier }
            .enumerated()
            .map { index, identity in
                UPnPMediaTargetDiscoveryCandidate(
                    identity: identity,
                    ordinal: index + 1
                )
            }
    }
}
