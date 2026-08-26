import Foundation
import MediaControlCore

public protocol UPnPMediaTargetResolving: Sendable {
    func resolve() async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor
    func invalidateResolution() async
}

extension UPnPMediaTargetResolver: UPnPMediaTargetResolving {
    public func invalidateResolution() async {
        invalidate()
    }
}

public protocol UPnPMediaTargetRenderingControlling: Sendable {
    func getVolume() async throws(UPnPMediaTargetError) -> Int
    func setVolume(_ volume: Int) async throws(UPnPMediaTargetError)
    func getMute() async throws(UPnPMediaTargetError) -> Bool
    func setMute(_ isMuted: Bool) async throws(UPnPMediaTargetError)
}

extension UPnPMediaTargetRenderingControlTransport: UPnPMediaTargetRenderingControlling {}

public typealias UPnPMediaTargetRenderingControlFactory = @Sendable (
    URL
) throws(UPnPMediaTargetError) -> any UPnPMediaTargetRenderingControlling

public actor UPnPMediaVolumeTarget: MediaVolumeTarget {
    private enum TargetAction: Sendable {
        case readState
        case apply(MediaTargetVolumeOperation)
    }

    private struct OperationWaiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    public nonisolated let identity: MediaTargetIdentity

    private let resolver: any UPnPMediaTargetResolving
    private let renderingControlFactory: UPnPMediaTargetRenderingControlFactory
    private let reconciler = MediaTargetVolumeReconciler()
    private var operationActive = false
    private var operationWaiters: [OperationWaiter] = []
    private var nextOperationWaiterID: UInt64 = 0

    public init(
        identity: MediaTargetIdentity,
        resolver: any UPnPMediaTargetResolving,
        renderingControlFactory: @escaping UPnPMediaTargetRenderingControlFactory = { endpoint in
            try UPnPMediaTargetRenderingControlTransport(endpoint: endpoint)
        }
    ) {
        self.identity = identity
        self.resolver = resolver
        self.renderingControlFactory = renderingControlFactory
    }

    var pendingOperationCount: Int {
        operationWaiters.count
    }

    public func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        guard await acquireOperation() else {
            throw .cancelled
        }
        defer { releaseOperation() }

        do {
            return try await performWithStaleEndpointRetry(.readState)
        } catch let error {
            throw Self.map(error)
        }
    }

    public func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        if case let .setVolume(volume) = operation,
           !(0...Int(UInt16.max)).contains(volume) {
            throw .capabilityUnavailable
        }

        guard await acquireOperation() else {
            throw .cancelled
        }
        defer { releaseOperation() }

        let confirmedState: MediaTargetVolumeState
        do {
            confirmedState = try await performWithStaleEndpointRetry(
                .apply(operation)
            )
        } catch let error {
            throw Self.map(error)
        }

        return try reconciler.verify(
            operation,
            confirmedState: confirmedState
        )
    }

    private func performWithStaleEndpointRetry(
        _ action: TargetAction
    ) async throws(UPnPMediaTargetError) -> MediaTargetVolumeState {
        for attempt in 0...1 {
            guard !Task.isCancelled else {
                throw .cancelled
            }

            do {
                let descriptor = try await resolver.resolve()
                guard descriptor.identity == identity else {
                    throw UPnPMediaTargetError.discoveryUnavailable
                }
                let controller = try renderingControlFactory(
                    descriptor.renderingControlURL
                )
                return try await Self.perform(action, using: controller)
            } catch let error as UPnPMediaTargetError {
                guard attempt == 0, error.isStaleEndpointRetryable else {
                    throw error
                }
                await resolver.invalidateResolution()
            } catch {
                throw .offline
            }
        }

        throw .offline
    }

    private static func perform(
        _ action: TargetAction,
        using controller: any UPnPMediaTargetRenderingControlling
    ) async throws(UPnPMediaTargetError) -> MediaTargetVolumeState {
        switch action {
        case .readState:
            break
        case let .apply(operation):
            guard !Task.isCancelled else {
                throw .cancelled
            }
            switch operation {
            case let .setVolume(volume):
                try await controller.setVolume(volume)
            case let .setMuted(isMuted):
                try await controller.setMute(isMuted)
            }
        }

        guard !Task.isCancelled else {
            throw .cancelled
        }
        return try await readState(using: controller)
    }

    private static func readState(
        using controller: any UPnPMediaTargetRenderingControlling
    ) async throws(UPnPMediaTargetError) -> MediaTargetVolumeState {
        guard !Task.isCancelled else {
            throw .cancelled
        }
        let volume = try await controller.getVolume()
        guard !Task.isCancelled else {
            throw .cancelled
        }
        let isMuted = try await controller.getMute()
        return MediaTargetVolumeState(
            absoluteVolume: volume,
            isMuted: isMuted,
            minimumVolume: 0,
            maximumVolume: Int(UInt16.max)
        )
    }

    private func acquireOperation() async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        if !operationActive {
            operationActive = true
            return true
        }

        let waiterID = nextOperationWaiterID
        nextOperationWaiterID &+= 1
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    operationWaiters.append(
                        OperationWaiter(
                            id: waiterID,
                            continuation: continuation
                        )
                    )
                }
            }
        }, onCancel: {
            Task {
                await self.cancelOperationWaiter(waiterID)
            }
        })
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationActive = false
            return
        }
        let waiter = operationWaiters.removeFirst()
        waiter.continuation.resume(returning: true)
    }

    private func cancelOperationWaiter(_ waiterID: UInt64) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        let waiter = operationWaiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private static func map(_ error: UPnPMediaTargetError) -> MediaTargetFailure {
        switch error {
        case .authenticationRejected:
            return .authenticationRejected
        case .discoveryUnavailable:
            return .discoveryUnavailable
        case .offline:
            return .offline
        case .timeout:
            return .timeout
        case .cancelled:
            return .cancelled
        case .missingRenderingControlService,
             .missingRenderingControlControlURL,
             .invalidRequestValue:
            return .capabilityUnavailable
        case .unexpectedStatusCode,
             .protocolFault:
            return .protocolFault
        case .unsupportedScheme,
             .userInfoPresent,
             .fragmentPresent,
             .invalidPort,
             .unsafeHost,
             .oversizedURL,
             .oversizedPayload,
             .forbiddenMarkup,
             .malformedXML,
             .invalidResponseValue,
             .redirectRejected,
             .nonHTTPResponse,
             .missingStableIdentity,
             .invalidControlURL,
             .malformedSSDPResponse:
            return .malformedResponse
        }
    }
}

private extension UPnPMediaTargetError {
    var isStaleEndpointRetryable: Bool {
        switch self {
        case .offline, .timeout:
            return true
        default:
            return false
        }
    }
}
