import Foundation

public enum UPnPMediaTargetError: Error, Equatable, Sendable {
    case unsupportedScheme
    case userInfoPresent
    case fragmentPresent
    case invalidPort
    case unsafeHost
    case oversizedURL
    case oversizedPayload
    case forbiddenMarkup
    case malformedXML
    case invalidRequestValue
    case invalidResponseValue
    case redirectRejected
    case authenticationRejected
    case nonHTTPResponse
    case unexpectedStatusCode(Int)
    case protocolFault
    case offline
    case timeout
    case cancelled
    case missingStableIdentity
    case missingRenderingControlService
    case missingRenderingControlControlURL
    case invalidControlURL
}
