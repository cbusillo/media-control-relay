import Foundation
import MediaControlCore
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP discovery and resolution", .serialized)
struct UPnPMediaTargetDiscoveryTests {
    @Test("SSDP multicast send denial remains distinct from offline failures")
    func classifiesSSDPSendFailures() {
        #expect(
            UPnPMediaTargetSSDPSocketFailure.classifySendError(EHOSTUNREACH)
                == .localNetworkDenied
        )

        for errorCode in [EPERM, EACCES, ENETDOWN, ENETUNREACH, EADDRNOTAVAIL] {
            #expect(
                UPnPMediaTargetSSDPSocketFailure.classifySendError(errorCode)
                    == .offline
            )
        }
    }

    @Test("Resolver preserves local-network denial from SSDP search")
    func resolverPreservesLocalNetworkDenial() async {
        let resolver = UPnPMediaTargetResolver(
            identity: MediaTargetIdentity(stableIdentifier: "uuid:fixture-target"),
            searcher: FailingSearcher(error: .localNetworkDenied),
            descriptorFetcher: SequencedDescriptorFetcher(values: [:])
        )

        await #expect(throws: UPnPMediaTargetError.localNetworkDenied) {
            _ = try await resolver.resolve()
        }
    }

    @Test("SSDP parsing is case-insensitive and exposes only validated fields")
    func parsesResponse() throws {
        let response = try UPnPMediaTargetSSDPResponseParser.parse(
            makeSSDPResponse(
                location: makeHTTPURL([10, 20, 30, 40], "/description.xml"),
                usn: "UUID:FIXTURE-TARGET::urn:schemas-upnp-org:device:MediaRenderer:1",
                headerCase: true
            )
        )

        #expect(response.location == makeHTTPURL([10, 20, 30, 40], "/description.xml"))
        #expect(response.usn == "UUID:FIXTURE-TARGET::urn:schemas-upnp-org:device:MediaRenderer:1")
        #expect(response.identity == MediaTargetIdentity(stableIdentifier: "uuid:fixture-target"))

        let sourceBound = try UPnPMediaTargetSSDPResponseParser.parse(
            makeSSDPResponse(
                location: makeHTTPURL([10, 20, 30, 40], "/description.xml"),
                usn: "uuid:fixture-target"
            ),
            sourceIPv4Host: [10, 20, 30, 40].map(String.init).joined(separator: ".")
        )
        #expect(sourceBound.identity == response.identity)

        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try UPnPMediaTargetSSDPResponseParser.parse(
                makeSSDPResponse(
                    location: makeHTTPURL([10, 20, 30, 40], "/description.xml"),
                    usn: "uuid:fixture-target"
                ),
                sourceIPv4Host: [10, 20, 30, 41].map(String.init).joined(separator: ".")
            )
        }
    }

    @Test("Malformed, duplicate, unsafe, and mismatched SSDP fields fail closed")
    func rejectsInvalidResponses() throws {
        let location = makeHTTPURL([10, 20, 30, 40], "/description.xml")
        let valid = makeSSDPResponse(location: location, usn: "uuid:fixture-target")

        let malformed: [Data] = [
            Data("HTTP/1.1 404 Not Found\r\nLOCATION: \(location.absoluteString)\r\nUSN: uuid:fixture-target\r\n\r\n".utf8),
            Data(valid.dropLast(2)),
            Data("HTTP/1.1 200 OK\r\nLOCATION \(location.absoluteString)\r\nUSN: uuid:fixture-target\r\n\r\n".utf8),
            Data("HTTP/1.1 200 OK\r\nLOCATION: \(location.absoluteString)\r\nLOCATION: \(location.absoluteString)\r\nUSN: uuid:fixture-target\r\n\r\n".utf8),
            Data("HTTP/1.1 200 OK\r\nLOCATION: \(location.absoluteString)\r\nUSN: not-a-uuid\r\n\r\n".utf8),
            Data(valid).replacing(Data("EXT:\r\n".utf8), with: Data()),
            Data(valid).replacing(Data("EXT:\r\n".utf8), with: Data("EXT: value\r\n".utf8)),
        ]

        for payload in malformed {
            #expect(throws: UPnPMediaTargetError.malformedSSDPResponse) {
                try UPnPMediaTargetSSDPResponseParser.parse(payload)
            }
        }

        var unsafeComponents = URLComponents(url: location, resolvingAgainstBaseURL: false)!
        unsafeComponents.scheme = "https"
        let unsafeLocation = Data(
            "HTTP/1.1 200 OK\r\nLOCATION: \(unsafeComponents.url!.absoluteString)\r\nUSN: uuid:fixture-target::urn:schemas-upnp-org:device:MediaRenderer:1\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n".utf8
        )
        #expect(throws: UPnPMediaTargetError.unsupportedScheme) {
            try UPnPMediaTargetSSDPResponseParser.parse(unsafeLocation)
        }

        let mismatchedTarget = Data(
            "HTTP/1.1 200 OK\r\nLOCATION: \(location.absoluteString)\r\nUSN: uuid:fixture-target::urn:schemas-upnp-org:device:MediaRenderer:1\r\nST: urn:schemas-upnp-org:device:mediarenderer:1\r\n\r\n".utf8
        )
        #expect(throws: UPnPMediaTargetError.malformedSSDPResponse) {
            try UPnPMediaTargetSSDPResponseParser.parse(mismatchedTarget)
        }

    }

    @Test("Descriptor fetch requires exact HTTP 200 and the original URL")
    func descriptorFetchPolicy() async throws {
        let location = makeHTTPURL([10, 20, 30, 41], "/description.xml")
        let descriptorXML = makeDescriptionXML(
            identity: "UUID:FIXTURE-TARGET",
            controlURL: "/rendering/control"
        )
        let serviceXML = makeServiceDescriptionXML()

        let success = StubHTTPTransport(
            responses: [
                (descriptorXML, makeHTTPResponse(url: location, statusCode: 200)),
                (serviceXML, makeHTTPResponse(url: makeHTTPURL([10, 20, 30, 41], "/rendering/scpd.xml"), statusCode: 200)),
            ]
        )
        let fetcher = UPnPMediaTargetURLSessionDescriptorFetcher(http: success)
        let descriptor = try await fetcher.fetch(location: location)
        #expect(descriptor.identity == MediaTargetIdentity(stableIdentifier: "uuid:fixture-target"))
        #expect(descriptor.renderingControlURL == makeHTTPURL([10, 20, 30, 41], "/rendering/control"))
        #expect(success.requestedURLs == [
            location,
            makeHTTPURL([10, 20, 30, 41], "/rendering/scpd.xml"),
        ])
        #expect(success.responseLimits == [
            UPnPMediaTargetURLSessionDescriptorFetcher.defaultMaximumDeviceDescriptionBytes,
            UPnPMediaTargetURLSessionDescriptorFetcher.defaultMaximumServiceDescriptionBytes,
        ])

        let changedURL = StubHTTPTransport(
            responses: [
                (descriptorXML, makeHTTPResponse(
                    url: makeHTTPURL([10, 20, 30, 42], "/description.xml"),
                    statusCode: 200
                )),
            ]
        )
        await #expect(throws: UPnPMediaTargetError.redirectRejected) {
            _ = try await UPnPMediaTargetURLSessionDescriptorFetcher(http: changedURL)
                .fetch(location: location)
        }

        let notOK = StubHTTPTransport(
            responses: [
                (descriptorXML, makeHTTPResponse(url: location, statusCode: 204)),
            ]
        )
        await #expect(throws: UPnPMediaTargetError.unexpectedStatusCode(204)) {
            _ = try await UPnPMediaTargetURLSessionDescriptorFetcher(http: notOK)
                .fetch(location: location)
        }
    }

    @Test("Service-description fetch requires exact HTTP 200 and the requested URL")
    func serviceDescriptionFetchPolicy() async {
        let location = makeHTTPURL([10, 20, 30, 45], "/description.xml")
        let serviceURL = makeHTTPURL([10, 20, 30, 45], "/rendering/scpd.xml")
        let descriptorXML = makeDescriptionXML(
            identity: "UUID:FIXTURE-TARGET",
            controlURL: "/rendering/control"
        )

        let changedURL = StubHTTPTransport(
            responses: [
                (descriptorXML, makeHTTPResponse(url: location, statusCode: 200)),
                (makeServiceDescriptionXML(), makeHTTPResponse(
                    url: makeHTTPURL([10, 20, 30, 46], "/rendering/scpd.xml"),
                    statusCode: 200
                )),
            ]
        )
        await #expect(throws: UPnPMediaTargetError.redirectRejected) {
            _ = try await UPnPMediaTargetURLSessionDescriptorFetcher(http: changedURL)
                .fetch(location: location)
        }

        let notOK = StubHTTPTransport(
            responses: [
                (descriptorXML, makeHTTPResponse(url: location, statusCode: 200)),
                (makeServiceDescriptionXML(), makeHTTPResponse(url: serviceURL, statusCode: 404)),
            ]
        )
        await #expect(throws: UPnPMediaTargetError.unexpectedStatusCode(404)) {
            _ = try await UPnPMediaTargetURLSessionDescriptorFetcher(http: notOK)
                .fetch(location: location)
        }
    }

    @Test("Resolver caches by generation and re-discovers changed endpoints")
    func cachesAndInvalidates() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let locationA = makeHTTPURL([10, 20, 30, 43], "/description.xml")
        let locationB = makeHTTPURL([10, 20, 30, 44], "/description.xml")
        let responseA = try UPnPMediaTargetSSDPResponse(location: locationA, usn: "uuid:fixture-target")
        let responseB = try UPnPMediaTargetSSDPResponse(location: locationB, usn: "uuid:fixture-target")
        let capabilityA = try UPnPMediaTargetVolumeCapability(
            minimumVolume: 0,
            maximumVolume: 100,
            step: 1
        )
        let capabilityB = try UPnPMediaTargetVolumeCapability(
            minimumVolume: 10,
            maximumVolume: 90,
            step: 5
        )
        let descriptorA = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: makeHTTPURL([10, 20, 30, 43], "/control/a"),
            volumeCapability: capabilityA
        )
        let descriptorB = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: makeHTTPURL([10, 20, 30, 44], "/control/b"),
            volumeCapability: capabilityB
        )
        let searcher = SequencedSearcher(responses: [[responseA], [responseB]])
        let fetcher = SequencedDescriptorFetcher(values: [locationA: .success(descriptorA), locationB: .success(descriptorB)])
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: searcher,
            descriptorFetcher: fetcher
        )

        #expect(try await resolver.resolve() == descriptorA)
        #expect(try await resolver.resolve() == descriptorA)
        #expect(searcher.callCount == 1)
        #expect(fetcher.locations == [locationA])

        await resolver.invalidate(for: .interfaceChanged)
        #expect(await resolver.currentGeneration == 1)
        #expect(try await resolver.resolve() == descriptorB)
        #expect((try await resolver.resolve()).volumeCapability == capabilityB)
        #expect(searcher.callCount == 2)
        #expect(fetcher.locations == [locationA, locationB])
    }

    @Test("Resolver skips duplicate candidates and mismatched descriptor identities")
    func skipsDuplicatesAndMismatches() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let duplicateLocation = makeHTTPURL([10, 20, 30, 45], "/description.xml")
        let mismatchLocation = makeHTTPURL([10, 20, 30, 46], "/description.xml")
        let goodLocation = makeHTTPURL([10, 20, 30, 47], "/description.xml")
        let duplicate = try UPnPMediaTargetSSDPResponse(location: duplicateLocation, usn: "uuid:fixture-target")
        let mismatch = try UPnPMediaTargetSSDPResponse(location: mismatchLocation, usn: "uuid:fixture-target")
        let good = try UPnPMediaTargetSSDPResponse(location: goodLocation, usn: "uuid:fixture-target")
        let expected = UPnPMediaTargetDescriptor(identity: identity, renderingControlURL: goodLocation)
        let wrong = UPnPMediaTargetDescriptor(
            identity: MediaTargetIdentity(stableIdentifier: "uuid:other-target"),
            renderingControlURL: mismatchLocation
        )
        let searcher = SequencedSearcher(responses: [[duplicate, duplicate, mismatch, good]])
        let fetcher = SequencedDescriptorFetcher(values: [
            duplicateLocation: .failure(.offline),
            mismatchLocation: .success(wrong),
            goodLocation: .success(expected),
        ])
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: searcher,
            descriptorFetcher: fetcher,
            searchBounds: UPnPMediaTargetSSDPSearchBounds(maximumCandidateCount: 4)
        )

        #expect(try await resolver.resolve() == expected)
        #expect(fetcher.locations == [duplicateLocation, mismatchLocation, goodLocation])
    }

    @Test("Resolver preserves semantic capability failures")
    func propagatesCapabilityFailure() async {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let location = makeHTTPURL([10, 20, 30, 48], "/description.xml")
        let response = try! UPnPMediaTargetSSDPResponse(location: location, usn: "uuid:fixture-target")
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: SequencedSearcher(responses: [[response]]),
            descriptorFetcher: SequencedDescriptorFetcher(values: [
                location: .failure(.missingVolumeCapability),
            ])
        )

        await #expect(throws: UPnPMediaTargetError.missingVolumeCapability) {
            _ = try await resolver.resolve()
        }
    }

    @Test("Resolver continues past a stale incapable location")
    func capabilityFailureDoesNotHideLaterValidLocation() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let staleLocation = makeHTTPURL([10, 20, 30, 49], "/description.xml")
        let validLocation = makeHTTPURL([10, 20, 30, 50], "/description.xml")
        let stale = try UPnPMediaTargetSSDPResponse(
            location: staleLocation,
            usn: "uuid:fixture-target"
        )
        let valid = try UPnPMediaTargetSSDPResponse(
            location: validLocation,
            usn: "uuid:fixture-target"
        )
        let expected = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: validLocation
        )
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: SequencedSearcher(responses: [[stale, valid]]),
            descriptorFetcher: SequencedDescriptorFetcher(values: [
                staleLocation: .failure(.missingVolumeCapability),
                validLocation: .success(expected),
            ])
        )

        #expect(try await resolver.resolve() == expected)
    }

    @Test("Resolver continues after a stale candidate timeout")
    func staleTimeoutDoesNotBlockLaterCandidate() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let staleLocation = makeHTTPURL([10, 20, 30, 60], "/description.xml")
        let currentLocation = makeHTTPURL([10, 20, 30, 61], "/description.xml")
        let responses = [
            try UPnPMediaTargetSSDPResponse(
                location: staleLocation,
                usn: "uuid:fixture-target"
            ),
            try UPnPMediaTargetSSDPResponse(
                location: currentLocation,
                usn: "uuid:fixture-target"
            ),
        ]
        let expected = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: currentLocation
        )
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: SequencedSearcher(responses: [responses]),
            descriptorFetcher: SequencedDescriptorFetcher(values: [
                staleLocation: .failure(.timeout),
                currentLocation: .success(expected),
            ])
        )

        #expect(try await resolver.resolve() == expected)
    }

    @Test("Resolver bounds candidates and does not use stale endpoints")
    func boundsCandidatesAndAvoidsStaleEndpoint() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let locations = (50...53).map { makeHTTPURL([10, 20, 30, $0], "/description.xml") }
        let responses = try locations.map {
            try UPnPMediaTargetSSDPResponse(location: $0, usn: "uuid:fixture-target")
        }
        let searcher = SequencedSearcher(responses: [responses])
        let fetcher = SequencedDescriptorFetcher(values: [:])
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: searcher,
            descriptorFetcher: fetcher,
            searchBounds: UPnPMediaTargetSSDPSearchBounds(maximumCandidateCount: 2)
        )

        await #expect(throws: UPnPMediaTargetError.discoveryUnavailable) {
            _ = try await resolver.resolve()
        }
        #expect(fetcher.locations == locations.prefix(2).map { $0 })

        let oldLocation = locations[0]
        let newLocation = locations[3]
        let oldDescriptor = UPnPMediaTargetDescriptor(identity: identity, renderingControlURL: oldLocation)
        let newDescriptor = UPnPMediaTargetDescriptor(identity: identity, renderingControlURL: newLocation)
        let changingSearcher = SequencedSearcher(responses: [[try UPnPMediaTargetSSDPResponse(location: oldLocation, usn: "uuid:fixture-target")], [try UPnPMediaTargetSSDPResponse(location: newLocation, usn: "uuid:fixture-target")]])
        let changingFetcher = SequencedDescriptorFetcher(values: [
            oldLocation: .success(oldDescriptor),
            newLocation: .success(newDescriptor),
        ])
        let changingResolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: changingSearcher,
            descriptorFetcher: changingFetcher
        )
        #expect(try await changingResolver.resolve() == oldDescriptor)
        await changingResolver.invalidate(for: .lifecycleChanged)
        #expect(try await changingResolver.resolve() == newDescriptor)
        #expect(changingFetcher.locations == [oldLocation, newLocation])
    }

    @Test("Resolver propagates search timeout and cancellation")
    func timeoutAndCancellation() async {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let timeoutResolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: FailingSearcher(error: .timeout),
            descriptorFetcher: SequencedDescriptorFetcher(values: [:])
        )
        await #expect(throws: UPnPMediaTargetError.timeout) {
            _ = try await timeoutResolver.resolve()
        }

        let cancellationResolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: HangingSearcher(),
            descriptorFetcher: SequencedDescriptorFetcher(values: [:])
        )
        let task = Task {
            try await cancellationResolver.resolve()
        }
        task.cancel()
        await #expect(throws: UPnPMediaTargetError.cancelled) {
            _ = try await task.value
        }
    }

    @Test("Invalidation during a fetch forces a new generation discovery")
    func invalidationDuringFetch() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let firstLocation = makeHTTPURL([10, 20, 30, 48], "/description.xml")
        let secondLocation = makeHTTPURL([10, 20, 30, 49], "/description.xml")
        let first = try UPnPMediaTargetSSDPResponse(location: firstLocation, usn: "uuid:fixture-target")
        let second = try UPnPMediaTargetSSDPResponse(location: secondLocation, usn: "uuid:fixture-target")
        let firstDescriptor = UPnPMediaTargetDescriptor(identity: identity, renderingControlURL: firstLocation)
        let secondDescriptor = UPnPMediaTargetDescriptor(identity: identity, renderingControlURL: secondLocation)
        let searcher = SequencedSearcher(responses: [[first], [second]])
        let fetcher = BlockingDescriptorFetcher(
            firstLocation: firstLocation,
            firstResult: firstDescriptor,
            secondLocation: secondLocation,
            secondResult: secondDescriptor
        )
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: searcher,
            descriptorFetcher: fetcher
        )

        let task = Task { try await resolver.resolve() }
        await fetcher.waitForFirstFetch()
        await resolver.invalidate(for: .interfaceChanged)
        await fetcher.releaseFirstFetch()

        #expect(try await task.value == secondDescriptor)
        #expect(searcher.callCount == 2)
        #expect(fetcher.locations == [firstLocation, secondLocation])
    }

    @Test("Concurrent resolution shares the cached generation result")
    func concurrentResolutionDoesNotOverwriteCache() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let location = makeHTTPURL([10, 20, 30, 62], "/description.xml")
        let response = try UPnPMediaTargetSSDPResponse(
            location: location,
            usn: "uuid:fixture-target"
        )
        let descriptor = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: location
        )
        let searcher = SequencedSearcher(responses: [[response]])
        let fetcher = BlockingDescriptorFetcher(
            firstLocation: location,
            firstResult: descriptor,
            secondLocation: location,
            secondResult: descriptor
        )
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: searcher,
            descriptorFetcher: fetcher
        )

        let first = Task { try await resolver.resolve() }
        await fetcher.waitForFirstFetch()
        let second = Task { try await resolver.resolve() }
        await fetcher.releaseFirstFetch()

        #expect(try await first.value == descriptor)
        #expect(try await second.value == descriptor)
        #expect(searcher.callCount == 1)
    }

    @Test("A cancelled queued resolution does not wait for the active fetch")
    func queuedResolutionCancellation() async throws {
        let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
        let location = makeHTTPURL([10, 20, 30, 63], "/description.xml")
        let response = try UPnPMediaTargetSSDPResponse(
            location: location,
            usn: "uuid:fixture-target"
        )
        let descriptor = UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: location
        )
        let fetcher = BlockingDescriptorFetcher(
            firstLocation: location,
            firstResult: descriptor,
            secondLocation: location,
            secondResult: descriptor
        )
        let resolver = UPnPMediaTargetResolver(
            identity: identity,
            searcher: SequencedSearcher(responses: [[response]]),
            descriptorFetcher: fetcher
        )

        let active = Task { try await resolver.resolve() }
        await fetcher.waitForFirstFetch()
        let queued = Task { try await resolver.resolve() }
        while await resolver.pendingResolutionCount == 0 {
            await Task.yield()
        }

        queued.cancel()
        var cancellationRemovedWaiter = false
        for _ in 0..<100 {
            if await resolver.pendingResolutionCount == 0 {
                cancellationRemovedWaiter = true
                break
            }
            await Task.yield()
        }
        #expect(cancellationRemovedWaiter)
        await #expect(throws: UPnPMediaTargetError.cancelled) {
            _ = try await queued.value
        }

        await fetcher.releaseFirstFetch()
        #expect(try await active.value == descriptor)
    }
}

private final class StubHTTPTransport: UPnPMediaTargetHTTPTransacting, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [(Data, HTTPURLResponse)]
    private var index = 0
    private(set) var requestedURLs: [URL] = []
    private(set) var responseLimits: [Int] = []

    init(data: Data, response: HTTPURLResponse) {
        responses = [(data, response)]
    }

    init(responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> (Data, HTTPURLResponse) {
        withLock {
            requestedURLs.append(request.url!)
            responseLimits.append(maximumResponseBytes)
            let response = responses[min(index, responses.count - 1)]
            index += 1
            return response
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class SequencedSearcher: UPnPMediaTargetSSDPSearching, @unchecked Sendable {
    private let lock = NSLock()
    private let responseSequences: [[UPnPMediaTargetSSDPResponse]]
    private var index = 0

    init(responses: [[UPnPMediaTargetSSDPResponse]]) {
        responseSequences = responses
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        withLock {
            let response = responseSequences[min(index, responseSequences.count - 1)]
            index += 1
            return response
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class SequencedDescriptorFetcher: UPnPMediaTargetDescriptorFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let values: [URL: Result<UPnPMediaTargetDescriptor, UPnPMediaTargetError>]
    private(set) var locations: [URL] = []

    init(values: [URL: Result<UPnPMediaTargetDescriptor, UPnPMediaTargetError>]) {
        self.values = values
    }

    func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        let value = withLock {
            locations.append(location)
            return values[location] ?? .failure(.offline)
        }
        return try value.get()
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private struct FailingSearcher: UPnPMediaTargetSSDPSearching {
    let error: UPnPMediaTargetError

    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        throw error
    }
}

private struct HangingSearcher: UPnPMediaTargetSSDPSearching {
    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
            throw .cancelled
        }
        return []
    }
}

private final class BlockingDescriptorFetcher: UPnPMediaTargetDescriptorFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let firstLocation: URL
    private let firstResult: UPnPMediaTargetDescriptor
    private let secondLocation: URL
    private let secondResult: UPnPMediaTargetDescriptor
    private var firstFetchStarted = false
    private var releaseFirst = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var locations: [URL] = []

    init(
        firstLocation: URL,
        firstResult: UPnPMediaTargetDescriptor,
        secondLocation: URL,
        secondResult: UPnPMediaTargetDescriptor
    ) {
        self.firstLocation = firstLocation
        self.firstResult = firstResult
        self.secondLocation = secondLocation
        self.secondResult = secondResult
    }

    func waitForFirstFetch() async {
        while true {
            let started = withLock { firstFetchStarted }
            if started { return }
            await Task.yield()
        }
    }

    func releaseFirstFetch() async {
        let continuation = withLock {
            releaseFirst = true
            let continuation = releaseContinuation
            releaseContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        if location == firstLocation {
            let alreadyReleased = withLock {
                firstFetchStarted = true
                locations.append(location)
                return releaseFirst
            }
            if !alreadyReleased {
                await withCheckedContinuation { continuation in
                    let shouldResume = withLock {
                        if releaseFirst {
                            return true
                        }
                        releaseContinuation = continuation
                        return false
                    }
                    if shouldResume {
                        continuation.resume()
                    }
                }
            }
            return firstResult
        }

        withLock { locations.append(location) }
        guard location == secondLocation else { throw .offline }
        return secondResult
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private func makeSSDPResponse(
    location: URL,
    usn: String,
    headerCase: Bool = false
) -> Data {
    let locationName = headerCase ? "lOcAtIoN" : "LOCATION"
    let usnName = headerCase ? "uSn" : "USN"
    let responseUSN = usn.contains("::")
        ? usn
        : usn + "::" + UPnPMediaTargetSSDP.searchTarget
    return Data(
        "HTTP/1.1 200 OK\r\n\(locationName): \(location.absoluteString)\r\n\(usnName): \(responseUSN)\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nEXT:\r\nBOOTID.UPNP.ORG: 1\r\n\r\n".utf8
    )
}

private extension Data {
    func replacing(_ target: Data, with replacement: Data) -> Data {
        guard let range = range(of: target) else {
            return self
        }
        var result = self
        result.replaceSubrange(range, with: replacement)
        return result
    }
}

private func makeHTTPURL(_ octets: [Int], _ path: String) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = octets.map(String.init).joined(separator: ".")
    components.path = path
    return components.url!
}

private func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
}

private func makeDescriptionXML(identity: String, controlURL: String) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <root>
          <device>
            <UDN>\(identity)</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <controlURL>\(controlURL)</controlURL>
                <SCPDURL>/rendering/scpd.xml</SCPDURL>
              </service>
            </serviceList>
          </device>
        </root>
        """.utf8
    )
}

private func makeServiceDescriptionXML() -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd>
          <serviceStateTable>
            <stateVariable>
              <name>Volume</name>
              <dataType>ui2</dataType>
              <allowedValueRange>
                <maximum>100</maximum>
              </allowedValueRange>
            </stateVariable>
          </serviceStateTable>
        </scpd>
        """.utf8
    )
}
