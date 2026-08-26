import Darwin
import Foundation
import MediaControlCore

public struct UPnPMediaTargetSSDPResponse: Equatable, Sendable {
    public let location: URL
    public let usn: String
    public let identity: MediaTargetIdentity

    public init(
        location: URL,
        usn: String
    ) throws(UPnPMediaTargetError) {
        self.location = try UPnPMediaTargetEndpointPolicy.validate(location)
        let parsed = try UPnPMediaTargetSSDPResponseParser.parseUSN(usn)
        self.usn = parsed.usn
        self.identity = parsed.identity
    }
}

public enum UPnPMediaTargetSSDPResponseParser {
    public static let defaultMaximumPayloadBytes = 8 * 1024

    public static func parse(
        _ data: Data,
        sourceIPv4Host: String? = nil,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetSSDPResponse {
        guard maximumPayloadBytes > 0, data.count <= maximumPayloadBytes else {
            throw .oversizedPayload
        }

        let delimiter = Data([13, 10, 13, 10])
        guard let delimiterRange = data.range(of: delimiter),
              delimiterRange.upperBound == data.endIndex else {
            throw .malformedSSDPResponse
        }

        let headerData = data[..<delimiterRange.lowerBound]
        guard let text = String(data: headerData, encoding: .utf8) else {
            throw .malformedSSDPResponse
        }

        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first,
              isExpectedStatusLine(statusLine),
              lines.count > 1 else {
            throw .malformedSSDPResponse
        }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty,
                  let separator = line.firstIndex(of: ":"),
                  separator != line.startIndex else {
                throw .malformedSSDPResponse
            }

            let name = String(line[..<separator])
            guard isValidHeaderName(name) else {
                throw .malformedSSDPResponse
            }
            let valueStart = line.index(after: separator)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            let key = name.lowercased()
            guard isValidHeaderValue(value),
                  !value.isEmpty || key == "ext" else {
                throw .malformedSSDPResponse
            }
            guard fields[key] == nil else {
                throw .malformedSSDPResponse
            }
            fields[key] = value
        }

        guard let locationText = fields["location"],
              let location = URL(string: locationText) else {
            throw .malformedSSDPResponse
        }
        let validatedLocation = try UPnPMediaTargetEndpointPolicy.validate(location)
        if let sourceIPv4Host,
           validatedLocation.host != sourceIPv4Host {
            throw .unsafeHost
        }

        guard let usn = fields["usn"] else {
            throw .malformedSSDPResponse
        }
        guard fields["ext"] == "" else {
            throw .malformedSSDPResponse
        }
        guard let searchTarget = fields["st"],
              searchTarget == UPnPMediaTargetSSDP.searchTarget else {
            throw .malformedSSDPResponse
        }
        let usnComponents = usn.components(separatedBy: "::")
        guard usnComponents.count == 2,
              usnComponents[1] == searchTarget else {
            throw .malformedSSDPResponse
        }
        return try UPnPMediaTargetSSDPResponse(
            location: validatedLocation,
            usn: usn
        )
    }

    fileprivate static func parseUSN(
        _ value: String
    ) throws(UPnPMediaTargetError) -> (usn: String, identity: MediaTargetIdentity) {
        guard !value.isEmpty,
              value.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw .malformedSSDPResponse
        }

        let components = value.components(separatedBy: "::")
        guard components.count <= 2,
              let uuid = components.first,
              uuid.count > 5,
              uuid.prefix(5).lowercased() == "uuid:" else {
            throw .malformedSSDPResponse
        }

        if components.count == 2, components[1].isEmpty {
            throw .malformedSSDPResponse
        }

        guard let identity = UPnPMediaTargetIdentityParser.parse(uuid) else {
            throw .malformedSSDPResponse
        }
        return (
            usn: value,
            identity: identity
        )
    }

    private static func isExpectedStatusLine(_ line: String) -> Bool {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        return parts.count == 3
            && parts[0].lowercased() == "http/1.1"
            && parts[1] == "200"
            && parts[2].lowercased() == "ok"
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || [33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126].contains(byte)
        }
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            byte == 9 || (32...126).contains(byte)
        }
    }
}

public enum UPnPMediaTargetSSDP {
    public static let searchTarget =
        "urn:schemas-upnp-org:device:MediaRenderer:1"
    public static let multicastHost = "239.255.255.250"
    public static let multicastPort: UInt16 = 1900
}

public struct UPnPMediaTargetSSDPSearchBounds: Equatable, Sendable {
    public static let `default` = UPnPMediaTargetSSDPSearchBounds()
    public static let maximumTimeoutInterval: TimeInterval = 5
    public static let maximumAllowedResponseBytes = UPnPMediaTargetSSDPResponseParser.defaultMaximumPayloadBytes
    public static let maximumAllowedCandidateCount = 16

    public let timeoutInterval: TimeInterval
    public let maximumResponseBytes: Int
    public let maximumCandidateCount: Int

    public init(
        timeoutInterval: TimeInterval = 1,
        maximumResponseBytes: Int = UPnPMediaTargetSSDPResponseParser.defaultMaximumPayloadBytes,
        maximumCandidateCount: Int = 8
    ) {
        self.timeoutInterval = min(
            max(0.01, timeoutInterval),
            Self.maximumTimeoutInterval
        )
        self.maximumResponseBytes = min(
            max(1, maximumResponseBytes),
            Self.maximumAllowedResponseBytes
        )
        self.maximumCandidateCount = min(
            max(1, maximumCandidateCount),
            Self.maximumAllowedCandidateCount
        )
    }
}

public protocol UPnPMediaTargetSSDPSearching: Sendable {
    func search(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse]
}

public final class UPnPMediaTargetIPv4SSDPSearcher: UPnPMediaTargetSSDPSearching, @unchecked Sendable {
    public init() {}

    public func search(
        bounds: UPnPMediaTargetSSDPSearchBounds = .default
    ) async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        do {
            return try await searchUnconditionally(bounds: bounds)
        } catch let error as UPnPMediaTargetError {
            throw error
        } catch {
            throw .offline
        }
    }

    private func searchUnconditionally(
        bounds: UPnPMediaTargetSSDPSearchBounds
    ) async throws -> [UPnPMediaTargetSSDPResponse] {
        let operation = SearchOperation(bounds: bounds)
        return try await withTaskCancellationHandler(operation: {
            try await operation.run()
        }, onCancel: {
            operation.cancel()
        })
    }
}

private final class SearchOperation: @unchecked Sendable {
    private let bounds: UPnPMediaTargetSSDPSearchBounds
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[UPnPMediaTargetSSDPResponse], UPnPMediaTargetError>?
    private var socketFD: Int32 = -1
    private var candidates: [UPnPMediaTargetSSDPResponse] = []
    private var candidatesByKey = Set<String>()
    private var cancellationRequested = false
    private var finished = false

    init(bounds: UPnPMediaTargetSSDPSearchBounds) {
        self.bounds = bounds
    }

    func run() async throws(UPnPMediaTargetError) -> [UPnPMediaTargetSSDPResponse] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UPnPMediaTargetSSDPResponse], UPnPMediaTargetError>) in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume(throwing: .cancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.performSearch()
            }
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    private func performSearch() {
        guard !isCancellationRequested else {
            finish(.failure(.cancelled))
            return
        }
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else {
            finishWithNetworkResult(.offline)
            return
        }
        guard installSocket(descriptor) else {
            finish(.failure(.cancelled))
            return
        }
        defer { closeSocketIfCurrent(descriptor) }

        guard bindEphemeralSocket(descriptor), let destination = makeMulticastDestination() else {
            finishWithNetworkResult(.offline)
            return
        }
        guard !isCancellationRequested else {
            finish(.failure(.cancelled))
            return
        }

        let request = Data(
            "M-SEARCH * HTTP/1.1\r\nHOST: \(UPnPMediaTargetSSDP.multicastHost):\(UPnPMediaTargetSSDP.multicastPort)\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(UPnPMediaTargetSSDP.searchTarget)\r\n\r\n".utf8
        )
        let sent = request.withUnsafeBytes { bytes in
            withUnsafePointer(to: destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(
                        descriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        address,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sent == request.count else {
            finishWithNetworkResult(.offline)
            return
        }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(bounds.timeoutInterval * 1_000_000_000)
        while true {
            guard !isCancellationRequested else {
                finish(.failure(.cancelled))
                return
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else {
                finishWithNetworkResult(.timeout)
                return
            }
            let remainingMilliseconds = max(
                1,
                min(
                    100,
                    Int64((deadline - now) / 1_000_000)
                )
            )

            var pollDescriptor = pollfd(
                fd: descriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let pollResult = poll(&pollDescriptor, 1, Int32(remainingMilliseconds))
            if pollResult < 0 {
                if errno == EINTR { continue }
                finishWithNetworkResult(.offline)
                return
            }
            if pollResult == 0 { continue }
            guard !isCancellationRequested else {
                finish(.failure(.cancelled))
                return
            }
            guard pollDescriptor.revents & Int16(POLLIN) != 0 else {
                finishWithNetworkResult(.offline)
                return
            }

            var payload = [UInt8](repeating: 0, count: bounds.maximumResponseBytes + 1)
            var source = sockaddr_storage()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = payload.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &source) { sourcePointer in
                    sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                        recvfrom(
                            descriptor,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            address,
                            &sourceLength
                        )
                    }
                }
            }
            guard received >= 0 else {
                if errno == EINTR { continue }
                finishWithNetworkResult(.offline)
                return
            }
            guard received <= bounds.maximumResponseBytes else { continue }

            guard let sourceIPv4Host = sourceIPv4Host(from: source) else {
                continue
            }
            let data = Data(payload.prefix(Int(received)))
            guard let response = try? UPnPMediaTargetSSDPResponseParser.parse(
                data,
                sourceIPv4Host: sourceIPv4Host,
                maximumPayloadBytes: bounds.maximumResponseBytes
            ) else {
                continue
            }

            let key = response.location.absoluteString
            lock.lock()
            let isNew = candidatesByKey.insert(key).inserted
            if isNew {
                candidates.append(response)
            }
            let reachedLimit = candidates.count >= bounds.maximumCandidateCount
            let currentCandidates = candidates
            lock.unlock()
            if reachedLimit {
                finish(.success(currentCandidates))
                return
            }
        }
    }

    private func installSocket(_ descriptor: Int32) -> Bool {
        lock.lock()
        if finished || cancellationRequested {
            lock.unlock()
            close(descriptor)
            return false
        } else {
            socketFD = descriptor
            lock.unlock()
            return true
        }
    }

    private func bindEphemeralSocket(_ descriptor: Int32) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                bind(
                    descriptor,
                    addressPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }

    private func makeMulticastDestination() -> sockaddr_in? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UPnPMediaTargetSSDP.multicastPort.bigEndian
        let converted = UPnPMediaTargetSSDP.multicastHost.withCString { pointer in
            inet_pton(AF_INET, pointer, &address.sin_addr)
        }
        return converted == 1 ? address : nil
    }

    private func closeSocketIfCurrent(_ descriptor: Int32) {
        lock.lock()
        let shouldClose = socketFD == descriptor
        if shouldClose {
            socketFD = -1
        }
        lock.unlock()
        if shouldClose { close(descriptor) }
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func sourceIPv4Host(from source: sockaddr_storage) -> String? {
        guard Int32(source.ss_family) == AF_INET else {
            return nil
        }
        var source = source
        var address = withUnsafePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(
            AF_INET,
            &address,
            &buffer,
            socklen_t(INET_ADDRSTRLEN)
        ) != nil else {
            return nil
        }
        let bytes = buffer
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func finishWithNetworkResult(_ error: UPnPMediaTargetError) {
        lock.lock()
        let result: Result<[UPnPMediaTargetSSDPResponse], UPnPMediaTargetError>
        if cancellationRequested {
            result = .failure(.cancelled)
        } else if !candidates.isEmpty {
            result = .success(candidates)
        } else {
            result = .failure(error)
        }
        lock.unlock()
        finish(result)
    }

    private func finish(_ result: Result<[UPnPMediaTargetSSDPResponse], UPnPMediaTargetError>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
