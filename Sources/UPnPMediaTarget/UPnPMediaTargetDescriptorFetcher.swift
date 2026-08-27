import Foundation

public protocol UPnPMediaTargetDescriptorFetching: Sendable {
    func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor
}

public struct UPnPMediaTargetURLSessionDescriptorFetcher: UPnPMediaTargetDescriptorFetching, Sendable {
    public static let defaultMaximumDeviceDescriptionBytes =
        UPnPMediaTargetDeviceDescriptionParser.defaultMaximumPayloadBytes
    public static let defaultMaximumServiceDescriptionBytes =
        UPnPMediaTargetSCPDParser.defaultMaximumPayloadBytes

    private let http: any UPnPMediaTargetHTTPTransacting
    private let maximumDeviceDescriptionBytes: Int
    private let maximumServiceDescriptionBytes: Int

    public init(
        http: any UPnPMediaTargetHTTPTransacting = UPnPMediaTargetURLSessionHTTPTransport(
            maximumResponseBytes: defaultMaximumServiceDescriptionBytes
        ),
        maximumDeviceDescriptionBytes: Int = defaultMaximumDeviceDescriptionBytes,
        maximumServiceDescriptionBytes: Int = defaultMaximumServiceDescriptionBytes
    ) {
        self.http = http
        self.maximumDeviceDescriptionBytes = max(1, min(
            maximumDeviceDescriptionBytes,
            Self.defaultMaximumDeviceDescriptionBytes
        ))
        self.maximumServiceDescriptionBytes = max(1, min(
            maximumServiceDescriptionBytes,
            Self.defaultMaximumServiceDescriptionBytes
        ))
    }

    public func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        let validatedLocation = try UPnPMediaTargetEndpointPolicy.validate(location)
        let deviceData = try await get(
            at: validatedLocation,
            maximumResponseBytes: maximumDeviceDescriptionBytes
        )
        let deviceDescription = try UPnPMediaTargetDeviceDescriptionParser.parse(
            deviceData,
            location: validatedLocation,
            maximumPayloadBytes: maximumDeviceDescriptionBytes
        )
        let serviceData = try await get(
            at: deviceDescription.renderingControlSCPDURL,
            maximumResponseBytes: maximumServiceDescriptionBytes
        )
        let volumeCapability = try UPnPMediaTargetSCPDParser.parse(
            serviceData,
            maximumPayloadBytes: maximumServiceDescriptionBytes
        )

        return UPnPMediaTargetDescriptor(
            identity: deviceDescription.identity,
            renderingControlURL: deviceDescription.renderingControlURL,
            volumeCapability: volumeCapability
        )
    }

    private func get(
        at location: URL,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> Data {
        let validatedLocation = try UPnPMediaTargetEndpointPolicy.validate(location)
        var request = URLRequest(url: validatedLocation)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")

        let (data, response) = try await http.send(
            request,
            maximumResponseBytes: maximumResponseBytes
        )
        guard let responseURL = response.url else {
            throw .nonHTTPResponse
        }
        let validatedResponseURL = try UPnPMediaTargetEndpointPolicy.validate(responseURL)
        guard validatedResponseURL == validatedLocation else {
            throw .redirectRejected
        }
        guard response.statusCode == 200 else {
            throw .unexpectedStatusCode(response.statusCode)
        }
        return data
    }
}
