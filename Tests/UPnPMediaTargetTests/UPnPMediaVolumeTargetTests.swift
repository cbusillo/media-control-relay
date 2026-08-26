import Foundation
import MediaControlCore
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP media volume target", .serialized)
struct UPnPMediaVolumeTargetTests {
    @Test("State reads return the generic ui2 volume range")
    func readsState() async throws {
        let fixture = makeTargetFixture(
            descriptorOctets: [40],
            controllers: [
                40: [
                    ScriptedRenderingController(steps: [
                        .getVolume(.success(12)),
                        .getMute(.success(true)),
                    ]),
                ],
            ]
        )

        let state = try await fixture.target.readState()

        #expect(state.absoluteVolume == 12)
        #expect(state.isMuted)
        #expect(state.minimumVolume == 0)
        #expect(state.maximumVolume == Int(UInt16.max))
        #expect(await fixture.resolver.resolveCount == 1)
        #expect(fixture.factory.createdEndpoints == [makeControlURL(40)])
    }

    @Test("Set volume returns only matching read-back state")
    func setsVolumeWithReadBack() async throws {
        let controller = ScriptedRenderingController(steps: [
            .setVolume(21, nil),
            .getVolume(.success(21)),
            .getMute(.success(true)),
        ])
        let fixture = makeTargetFixture(
            descriptorOctets: [41],
            controllers: [41: [controller]]
        )

        let state = try await fixture.target.apply(.setVolume(21))

        #expect(state.absoluteVolume == 21)
        #expect(state.isMuted)
        #expect(await controller.recordedCalls == [
            .setVolume(21),
            .getVolume,
            .getMute,
        ])
    }

    @Test("Set mute returns only matching read-back state")
    func setsMuteWithReadBack() async throws {
        let controller = ScriptedRenderingController(steps: [
            .setMute(true, nil),
            .getVolume(.success(8)),
            .getMute(.success(true)),
        ])
        let fixture = makeTargetFixture(
            descriptorOctets: [42],
            controllers: [42: [controller]]
        )

        let state = try await fixture.target.apply(.setMuted(true))

        #expect(state.absoluteVolume == 8)
        #expect(state.isMuted)
        #expect(await controller.recordedCalls == [
            .setMute(true),
            .getVolume,
            .getMute,
        ])
    }

    @Test("Requested-dimension mismatches fail after full read-back")
    func rejectsReadBackMismatch() async {
        let controller = ScriptedRenderingController(steps: [
            .setVolume(30, nil),
            .getVolume(.success(29)),
            .getMute(.success(false)),
        ])
        let fixture = makeTargetFixture(
            descriptorOctets: [43],
            controllers: [43: [controller]]
        )

        await #expect(throws: MediaTargetFailure.readBackMismatch) {
            _ = try await fixture.target.apply(.setVolume(30))
        }
        #expect(await controller.recordedCalls == [
            .setVolume(30),
            .getVolume,
            .getMute,
        ])
    }

    @Test("Protocol, timeout, and cancellation errors map to neutral failures")
    func mapsTransportFailures() async {
        let cases: [(Int, UPnPMediaTargetError, MediaTargetFailure)] = [
            (44, .protocolFault, .protocolFault),
            (45, .timeout, .timeout),
            (46, .cancelled, .cancelled),
        ]

        for (octet, adapterError, expectedFailure) in cases {
            let controllers = adapterError == .timeout
                ? [
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(adapterError)),
                    ]),
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(adapterError)),
                    ]),
                ]
                : [
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(adapterError)),
                    ]),
                ]
            let fixture = makeTargetFixture(
                descriptorOctets: [octet],
                controllers: [octet: controllers]
            )

            await #expect(throws: expectedFailure) {
                _ = try await fixture.target.readState()
            }
        }
    }

    @Test("An offline stale endpoint is invalidated and resolved once")
    func reResolvesStaleEndpoint() async throws {
        let fixture = makeTargetFixture(
            descriptorOctets: [47, 48],
            controllers: [
                47: [
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(.offline)),
                    ]),
                ],
                48: [
                    ScriptedRenderingController(steps: [
                        .getVolume(.success(18)),
                        .getMute(.success(false)),
                    ]),
                ],
            ]
        )

        let state = try await fixture.target.readState()

        #expect(state.absoluteVolume == 18)
        #expect(await fixture.resolver.resolveCount == 2)
        #expect(await fixture.resolver.invalidationCount == 1)
        #expect(fixture.factory.createdEndpoints == [
            makeControlURL(47),
            makeControlURL(48),
        ])
    }

    @Test("An absolute write retries once on the freshly resolved endpoint")
    func retriesWriteOnFreshEndpoint() async throws {
        let staleController = ScriptedRenderingController(steps: [
            .setVolume(24, .offline),
        ])
        let freshController = ScriptedRenderingController(steps: [
            .setVolume(24, nil),
            .getVolume(.success(24)),
            .getMute(.success(false)),
        ])
        let fixture = makeTargetFixture(
            descriptorOctets: [55, 56],
            controllers: [
                55: [staleController],
                56: [freshController],
            ]
        )

        let state = try await fixture.target.apply(.setVolume(24))

        #expect(state.absoluteVolume == 24)
        #expect(await staleController.recordedCalls == [.setVolume(24)])
        #expect(await freshController.recordedCalls == [
            .setVolume(24),
            .getVolume,
            .getMute,
        ])
        #expect(await fixture.resolver.invalidationCount == 1)
        #expect(fixture.factory.createdEndpoints == [
            makeControlURL(55),
            makeControlURL(56),
        ])
    }

    @Test("Offline retry is bounded to one replacement endpoint")
    func boundsStaleEndpointRetry() async {
        let fixture = makeTargetFixture(
            descriptorOctets: [49, 50],
            controllers: [
                49: [
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(.offline)),
                    ]),
                ],
                50: [
                    ScriptedRenderingController(steps: [
                        .getVolume(.failure(.offline)),
                    ]),
                ],
            ]
        )

        await #expect(throws: MediaTargetFailure.offline) {
            _ = try await fixture.target.readState()
        }
        #expect(await fixture.resolver.resolveCount == 2)
        #expect(await fixture.resolver.invalidationCount == 1)
        #expect(fixture.factory.createdEndpoints.count == 2)
    }

    @Test("Concurrent operations remain serialized across awaits")
    func serializesConcurrentOperations() async throws {
        let blocking = BlockingReadController(volume: 7, isMuted: false)
        let second = ScriptedRenderingController(steps: [
            .getVolume(.success(9)),
            .getMute(.success(true)),
        ])
        let fixture = makeTargetFixture(
            descriptorOctets: [51],
            controllers: [51: [blocking, second]]
        )

        let firstTask = Task { try await fixture.target.readState() }
        await blocking.waitUntilReadStarted()
        let secondTask = Task { try await fixture.target.readState() }
        while await fixture.target.pendingOperationCount == 0 {
            await Task.yield()
        }

        #expect(await fixture.resolver.resolveCount == 1)
        #expect(fixture.factory.createdEndpoints.count == 1)

        await blocking.releaseRead()
        #expect(try await firstTask.value.absoluteVolume == 7)
        #expect(try await secondTask.value.absoluteVolume == 9)
        #expect(await fixture.resolver.resolveCount == 2)
        #expect(fixture.factory.createdEndpoints.count == 2)
    }

    @Test("A cancelled queued operation does not wait for the active request")
    func cancelsQueuedOperation() async throws {
        let blocking = BlockingReadController(volume: 6, isMuted: false)
        let fixture = makeTargetFixture(
            descriptorOctets: [52],
            controllers: [
                52: [
                    blocking,
                    ScriptedRenderingController(steps: [
                        .getVolume(.success(10)),
                        .getMute(.success(false)),
                    ]),
                ],
            ]
        )

        let active = Task { try await fixture.target.readState() }
        await blocking.waitUntilReadStarted()
        let queued = Task { try await fixture.target.readState() }
        while await fixture.target.pendingOperationCount == 0 {
            await Task.yield()
        }

        queued.cancel()
        var removed = false
        for _ in 0..<100 {
            if await fixture.target.pendingOperationCount == 0 {
                removed = true
                break
            }
            await Task.yield()
        }
        #expect(removed)
        await #expect(throws: MediaTargetFailure.cancelled) {
            _ = try await queued.value
        }

        await blocking.releaseRead()
        #expect(try await active.value.absoluteVolume == 6)
        #expect(fixture.factory.createdEndpoints.count == 1)
    }

    @Test("Apply cannot complete before requested read-back")
    func doesNotSucceedBeforeReadBack() async throws {
        let controller = BlockingReadBackController(
            expectedVolume: 23,
            confirmedVolume: 23,
            isMuted: false
        )
        let fixture = makeTargetFixture(
            descriptorOctets: [53],
            controllers: [53: [controller]]
        )
        let completion = CompletionRecorder()

        let task = Task {
            do {
                let state = try await fixture.target.apply(.setVolume(23))
                await completion.markCompleted()
                return state
            } catch {
                await completion.markCompleted()
                throw error
            }
        }
        await controller.waitUntilReadBackStarted()

        #expect(await completion.isCompleted == false)
        await controller.releaseReadBack()
        #expect(try await task.value.absoluteVolume == 23)
        #expect(await completion.isCompleted)
    }

    @Test("Values outside the generic ui2 range fail before discovery")
    func rejectsOutOfRangeVolume() async {
        let fixture = makeTargetFixture(
            descriptorOctets: [54],
            controllers: [:]
        )

        await #expect(throws: MediaTargetFailure.capabilityUnavailable) {
            _ = try await fixture.target.apply(.setVolume(Int(UInt16.max) + 1))
        }
        #expect(await fixture.resolver.resolveCount == 0)
        #expect(fixture.factory.createdEndpoints.isEmpty)
    }
}

private struct TargetFixture {
    let target: UPnPMediaVolumeTarget
    let resolver: TargetResolverStub
    let factory: TargetControllerFactory
}

private func makeTargetFixture(
    descriptorOctets: [Int],
    controllers: [Int: [any UPnPMediaTargetRenderingControlling]]
) -> TargetFixture {
    let identity = MediaTargetIdentity(stableIdentifier: "uuid:fixture-target")
    let descriptors = descriptorOctets.map {
        UPnPMediaTargetDescriptor(
            identity: identity,
            renderingControlURL: makeControlURL($0)
        )
    }
    let resolver = TargetResolverStub(descriptors: descriptors)
    let factory = TargetControllerFactory(
        controllers: Dictionary(uniqueKeysWithValues: controllers.map {
            (makeControlURL($0.key), $0.value)
        })
    )
    let renderingControlFactory: UPnPMediaTargetRenderingControlFactory = { endpoint in
        try factory.make(endpoint: endpoint)
    }
    let target = UPnPMediaVolumeTarget(
        identity: identity,
        resolver: resolver,
        renderingControlFactory: renderingControlFactory
    )
    return TargetFixture(target: target, resolver: resolver, factory: factory)
}

private actor TargetResolverStub: UPnPMediaTargetResolving {
    private let descriptors: [UPnPMediaTargetDescriptor]
    private var index = 0
    private(set) var invalidationCount = 0

    init(descriptors: [UPnPMediaTargetDescriptor]) {
        self.descriptors = descriptors
    }

    var resolveCount: Int {
        index
    }

    func resolve() async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        guard !descriptors.isEmpty else {
            throw .discoveryUnavailable
        }
        let descriptor = descriptors[min(index, descriptors.count - 1)]
        index += 1
        return descriptor
    }

    func invalidateResolution() async {
        invalidationCount += 1
    }
}

private final class TargetControllerFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var controllers: [URL: [any UPnPMediaTargetRenderingControlling]]
    private var endpoints: [URL] = []

    init(controllers: [URL: [any UPnPMediaTargetRenderingControlling]]) {
        self.controllers = controllers
    }

    var createdEndpoints: [URL] {
        withLock { endpoints }
    }

    func make(
        endpoint: URL
    ) throws(UPnPMediaTargetError) -> any UPnPMediaTargetRenderingControlling {
        lock.lock()
        defer { lock.unlock() }
        endpoints.append(endpoint)
        guard var values = controllers[endpoint], !values.isEmpty else {
            throw .offline
        }
        let controller = values.removeFirst()
        controllers[endpoint] = values
        return controller
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private enum ControllerOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(UPnPMediaTargetError)
}

private enum ControllerStep: Sendable {
    case getVolume(ControllerOutcome<Int>)
    case setVolume(Int, UPnPMediaTargetError?)
    case getMute(ControllerOutcome<Bool>)
    case setMute(Bool, UPnPMediaTargetError?)
}

private enum ControllerCall: Equatable, Sendable {
    case getVolume
    case setVolume(Int)
    case getMute
    case setMute(Bool)
}

private actor ScriptedRenderingController: UPnPMediaTargetRenderingControlling {
    private var steps: [ControllerStep]
    private(set) var recordedCalls: [ControllerCall] = []

    init(steps: [ControllerStep]) {
        self.steps = steps
    }

    func getVolume() async throws(UPnPMediaTargetError) -> Int {
        recordedCalls.append(.getVolume)
        guard !steps.isEmpty else { throw .protocolFault }
        let step = steps.removeFirst()
        guard case let .getVolume(outcome) = step else { throw .protocolFault }
        switch outcome {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }

    func setVolume(_ volume: Int) async throws(UPnPMediaTargetError) {
        recordedCalls.append(.setVolume(volume))
        guard !steps.isEmpty else { throw .protocolFault }
        let step = steps.removeFirst()
        guard case let .setVolume(expected, error) = step,
              expected == volume else {
            throw .protocolFault
        }
        if let error { throw error }
    }

    func getMute() async throws(UPnPMediaTargetError) -> Bool {
        recordedCalls.append(.getMute)
        guard !steps.isEmpty else { throw .protocolFault }
        let step = steps.removeFirst()
        guard case let .getMute(outcome) = step else { throw .protocolFault }
        switch outcome {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }

    func setMute(_ isMuted: Bool) async throws(UPnPMediaTargetError) {
        recordedCalls.append(.setMute(isMuted))
        guard !steps.isEmpty else { throw .protocolFault }
        let step = steps.removeFirst()
        guard case let .setMute(expected, error) = step,
              expected == isMuted else {
            throw .protocolFault
        }
        if let error { throw error }
    }
}

private actor BlockingReadController: UPnPMediaTargetRenderingControlling {
    private let volume: Int
    private let isMuted: Bool
    private var readStarted = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(volume: Int, isMuted: Bool) {
        self.volume = volume
        self.isMuted = isMuted
    }

    func waitUntilReadStarted() async {
        while !readStarted {
            await Task.yield()
        }
    }

    func releaseRead() {
        released = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func getVolume() async throws(UPnPMediaTargetError) -> Int {
        readStarted = true
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }
        return volume
    }

    func setVolume(_ volume: Int) async throws(UPnPMediaTargetError) {
        throw .protocolFault
    }

    func getMute() async throws(UPnPMediaTargetError) -> Bool {
        isMuted
    }

    func setMute(_ isMuted: Bool) async throws(UPnPMediaTargetError) {
        throw .protocolFault
    }
}

private actor BlockingReadBackController: UPnPMediaTargetRenderingControlling {
    private let expectedVolume: Int
    private let confirmedVolume: Int
    private let isMuted: Bool
    private var didSetVolume = false
    private var readBackStarted = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(expectedVolume: Int, confirmedVolume: Int, isMuted: Bool) {
        self.expectedVolume = expectedVolume
        self.confirmedVolume = confirmedVolume
        self.isMuted = isMuted
    }

    func waitUntilReadBackStarted() async {
        while !readBackStarted {
            await Task.yield()
        }
    }

    func releaseReadBack() {
        released = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func getVolume() async throws(UPnPMediaTargetError) -> Int {
        guard didSetVolume else { throw .protocolFault }
        readBackStarted = true
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }
        return confirmedVolume
    }

    func setVolume(_ volume: Int) async throws(UPnPMediaTargetError) {
        guard volume == expectedVolume else { throw .protocolFault }
        didSetVolume = true
    }

    func getMute() async throws(UPnPMediaTargetError) -> Bool {
        isMuted
    }

    func setMute(_ isMuted: Bool) async throws(UPnPMediaTargetError) {
        throw .protocolFault
    }
}

private actor CompletionRecorder {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

private func makeControlURL(_ finalOctet: Int) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = [10, 30, 40, finalOctet]
        .map(String.init)
        .joined(separator: ".")
    components.path = "/rendering/control"
    return components.url!
}
