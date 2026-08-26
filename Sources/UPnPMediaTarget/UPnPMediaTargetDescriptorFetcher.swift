import Foundation

public protocol UPnPMediaTargetDescriptorFetching: Sendable {
    func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor
}

public struct UPnPMediaTargetURLSessionDescriptorFetcher: UPnPMediaTargetDescriptorFetching, Sendable {
    public static let defaultMaximumResponseBytes =
        UPnPMediaTargetURLSessionHTTPTransport.defaultMaximumResponseBytes

    private let http: any UPnPMediaTargetHTTPTransacting
    private let maximumResponseBytes: Int

    public init(
        http: any UPnPMediaTargetHTTPTransacting = UPnPMediaTargetURLSessionHTTPTransport(),
        maximumResponseBytes: Int = defaultMaximumResponseBytes
    ) {
        self.http = http
        self.maximumResponseBytes = min(
            max(1, maximumResponseBytes),
            Self.defaultMaximumResponseBytes
        )
    }

    public func fetch(
        location: URL
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
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

        return try UPnPMediaTargetDeviceDescriptionParser.parse(
            data,
            location: validatedLocation,
            maximumPayloadBytes: maximumResponseBytes
        )
    }
}
