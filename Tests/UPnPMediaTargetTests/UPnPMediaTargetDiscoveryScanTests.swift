import Foundation
import MediaControlCore
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP discovery scan")
struct UPnPMediaTargetDiscoveryScanTests {
    @Test("Scan confirms identities and assigns deterministic ordinals")
    func confirmsCandidates() async throws {
        let firstURL = discoveryURL([10, 40, 0, 2], "/first.xml")
        let secondURL = discoveryURL([10, 40, 0, 3], "/second.xml")
        let first = try UPnPMediaTargetSSDPResponse(
            location: firstURL,
            usn: "uuid:renderer-b::urn:schemas-upnp-org:device:MediaRenderer:1"
        )
        let second = try UPnPMediaTargetSSDPResponse(
            location: secondURL,
            usn: "uuid:renderer-a::urn:schemas-upnp-org:device:MediaRenderer:1"
        )
        let scanner = UPnPMediaTargetDiscoveryScan(
            searcher: DiscoverySearcher(responses: [first, second]),
            descriptorFetcher: DiscoveryFetcher(descriptors: [
                firstURL: UPnPMediaTargetDescriptor(
                    identity: first.identity,
                    renderingControlURL: discoveryURL([10, 40, 0, 2], "/control")
                ),
                secondURL: UPnPMediaTargetDescriptor(
                    identity: second.identity,
                    renderingControlURL: discoveryURL([10, 40, 0, 3], "/control")
                ),
            ])
        )

        let candidates = try await scanner.scan()

        #expect(candidates.map(\.identity) == [second.identity, first.identity])
        #expect(candidates.map(\.ordinal) == [1, 2])
    }

    @Test("Scan rejects descriptor identity mismatches")
    func rejectsMismatchedIdentity() async throws {
        let location = discoveryURL([10, 40, 0, 4], "/device.xml")
        let response = try UPnPMediaTargetSSDPResponse(
            location: location,
            usn: "uuid:announced::urn:schemas-upnp-org:device:MediaRenderer:1"
        )
        let scanner = UPnPMediaTargetDiscoveryScan(
            searcher: DiscoverySearcher(responses: [response]),
            descriptorFetcher: DiscoveryFetcher(descriptors: [
                location: UPnPMediaTargetDescriptor(
                    identity: MediaTargetIdentity(stableIdentifier: "uuid:different"),
                    renderingControlURL: discoveryURL([10, 40, 0, 4], "/control")
                ),
            ])
        )

        #expect(try await scanner.scan().isEmpty)
    }

    @Test("A completed search with no responses is an empty scan")
    func timeoutIsEmpty() async throws {
        let scanner = UPnPMediaTargetDiscoveryScan(
            searcher: FailingDiscoverySearcher(error: .timeout),
            descriptorFetcher: DiscoveryFetcher(descriptors: [:])
        )

        #expect(try await scanner.scan().isEmpty)
    }
}

private struct DiscoverySearcher: UPnPMediaTargetSSDPSearching {
    let responses: [UPnPMediaTargetSSDPResponse]

    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        Array(responses.prefix(bounds.maximumCandidateCount))
    }
}

private struct DiscoveryFetcher: UPnPMediaTargetDescriptorFetching {
    let descriptors: [URL: UPnPMediaTargetDescriptor]

    func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        guard let descriptor = descriptors[location] else {
            throw .discoveryUnavailable
        }
        return descriptor
    }
}

private struct FailingDiscoverySearcher: UPnPMediaTargetSSDPSearching {
    let error: UPnPMediaTargetError

    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        throw error
    }
}

private func discoveryURL(_ octets: [Int], _ path: String) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = octets.map(String.init).joined(separator: ".")
    components.path = path
    return components.url!
}
