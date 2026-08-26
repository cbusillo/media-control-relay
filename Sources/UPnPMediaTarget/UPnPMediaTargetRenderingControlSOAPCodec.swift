import Foundation

public struct UPnPMediaTargetRenderingControlFault: Equatable, Sendable {
    public let code: UInt16

    public init(code: UInt16) {
        self.code = code
    }
}

public enum UPnPMediaTargetRenderingControlOperation: Equatable, Sendable {
    case getVolume
    case setVolume(Int)
    case getMute
    case setMute(Bool)

    var actionName: String {
        switch self {
        case .getVolume:
            return "GetVolume"
        case .setVolume:
            return "SetVolume"
        case .getMute:
            return "GetMute"
        case .setMute:
            return "SetMute"
        }
    }
}

public enum UPnPMediaTargetRenderingControlResponse: Equatable, Sendable {
    case volume(Int)
    case mute(Bool)
    case acknowledged
    case fault(UPnPMediaTargetRenderingControlFault)
}

public struct UPnPMediaTargetRenderingControlSOAPCodec: Sendable {
    public static let serviceType = UPnPMediaTargetDeviceDescriptionParser.renderingControlServiceType
    public static let instanceID = 0
    public static let channel = "Master"
    public static let defaultMaximumPayloadBytes = UPnPMediaTargetXMLGate.defaultMaximumPayloadBytes

    public init() {}

    public func makeRequest(
        endpoint: URL,
        operation: UPnPMediaTargetRenderingControlOperation
    ) throws(UPnPMediaTargetError) -> URLRequest {
        let validatedEndpoint = try UPnPMediaTargetEndpointPolicy.validate(endpoint)
        let actionName = operation.actionName
        let fields: String

        switch operation {
        case .getVolume, .getMute:
            fields = commonFields
        case let .setVolume(volume):
            guard UInt16(exactly: volume) != nil else {
                throw .invalidRequestValue
            }
            fields = commonFields + "<DesiredVolume>\(volume)</DesiredVolume>"
        case let .setMute(isMuted):
            fields = commonFields + "<DesiredMute>\(isMuted ? 1 : 0)</DesiredMute>"
        }

        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body><u:\(actionName) xmlns:u=\"\(Self.serviceType)\">"
            + fields
            + "</u:\(actionName)></s:Body></s:Envelope>"

        var request = URLRequest(url: validatedEndpoint)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "\"\(Self.serviceType)#\(actionName)\"",
            forHTTPHeaderField: "SOAPAction"
        )
        request.setValue(
            "text/xml; charset=\"utf-8\"",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("text/xml", forHTTPHeaderField: "Accept")
        return request
    }

    public func decodeResponse(
        _ data: Data,
        operation: UPnPMediaTargetRenderingControlOperation,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetRenderingControlResponse {
        guard !data.isEmpty else {
            throw .malformedXML
        }

        try UPnPMediaTargetXMLGate.validatePayload(
            data,
            maximumPayloadBytes: maximumPayloadBytes
        )

        let delegate = RenderingControlResponseDelegate(operation: operation)
        let parser = UPnPMediaTargetXMLGate.makeParser(data: data, delegate: delegate)
        guard parser.parse() else {
            throw delegate.error ?? .malformedXML
        }

        if let faultCode = delegate.faultCode {
            return .fault(UPnPMediaTargetRenderingControlFault(code: faultCode))
        }
        guard delegate.foundExpectedResponse else {
            throw .invalidResponseValue
        }

        switch operation {
        case .getVolume:
            guard let volume = delegate.currentVolume else {
                throw .invalidResponseValue
            }
            return .volume(Int(volume))
        case .getMute:
            guard let mute = delegate.currentMute else {
                throw .invalidResponseValue
            }
            return .mute(mute)
        case .setVolume, .setMute:
            return .acknowledged
        }
    }

    private var commonFields: String {
        "<InstanceID>\(Self.instanceID)</InstanceID>"
            + "<Channel>\(Self.channel)</Channel>"
    }
}

private final class RenderingControlResponseDelegate: NSObject, XMLParserDelegate {
    private static let soapEnvelopeNamespace = "http://schemas.xmlsoap.org/soap/envelope/"
    private static let upnpControlNamespace = "urn:schemas-upnp-org:control-1-0"

    let operation: UPnPMediaTargetRenderingControlOperation
    var currentVolume: UInt16?
    var currentMute: Bool?
    var faultCode: UInt16?
    var foundExpectedResponse = false
    var error: UPnPMediaTargetError?

    private struct Element: Equatable {
        let name: String
        let namespace: String
    }

    private var currentText = ""
    private var elementStack: [Element] = []
    private var foundEnvelope = false
    private var foundBody = false
    private var foundFault = false
    private var foundFaultCode = false
    private var foundFaultString = false
    private var foundFaultDetail = false
    private var foundUPnPError = false
    private var foundErrorDescription = false
    private var foundValue = false

    init(operation: UPnPMediaTargetRenderingControlOperation) {
        self.operation = operation
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(parser, with: .invalidResponseValue)
            return
        }
        currentText.removeAll(keepingCapacity: true)
        let element = Element(name: elementName, namespace: namespaceURI ?? "")
        let parent = elementStack.last

        if elementStack.isEmpty {
            guard element == Element(
                name: "Envelope",
                namespace: Self.soapEnvelopeNamespace
            ), !foundEnvelope else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            foundEnvelope = true
        } else if parent == Element(
            name: "Envelope",
            namespace: Self.soapEnvelopeNamespace
        ) {
            guard element == Element(
                name: "Body",
                namespace: Self.soapEnvelopeNamespace
            ), !foundBody else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            foundBody = true
        } else if parent == Element(
            name: "Body",
            namespace: Self.soapEnvelopeNamespace
        ) {
            let expectedResponse = Element(
                name: operation.actionName + "Response",
                namespace: UPnPMediaTargetRenderingControlSOAPCodec.serviceType
            )
            let fault = Element(
                name: "Fault",
                namespace: Self.soapEnvelopeNamespace
            )
            if element == expectedResponse, !foundExpectedResponse, !foundFault {
                foundExpectedResponse = true
            } else if element == fault, !foundFault, !foundExpectedResponse {
                foundFault = true
            } else {
                fail(parser, with: .invalidResponseValue)
                return
            }
        } else if parent == Element(
            name: operation.actionName + "Response",
            namespace: UPnPMediaTargetRenderingControlSOAPCodec.serviceType
        ) {
            guard isExpectedValueElement(element), !foundValue else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            foundValue = true
        } else if parent == Element(
            name: "Fault",
            namespace: Self.soapEnvelopeNamespace
        ) {
            guard element.namespace.isEmpty else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            switch element.name {
            case "faultcode" where !foundFaultCode:
                foundFaultCode = true
            case "faultstring" where !foundFaultString:
                foundFaultString = true
            case "detail" where !foundFaultDetail:
                foundFaultDetail = true
            default:
                fail(parser, with: .invalidResponseValue)
                return
            }
        } else if parent == Element(name: "detail", namespace: "") {
            guard element == Element(
                name: "UPnPError",
                namespace: Self.upnpControlNamespace
            ), foundFault, !foundUPnPError else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            foundUPnPError = true
        } else if parent == Element(
            name: "UPnPError",
            namespace: Self.upnpControlNamespace
        ) {
            guard element.namespace == Self.upnpControlNamespace else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            if element.name == "errorCode", faultCode == nil {
                // Parsed when the element closes.
            } else if element.name == "errorDescription", !foundErrorDescription {
                foundErrorDescription = true
            } else {
                fail(parser, with: .invalidResponseValue)
                return
            }
        } else {
            fail(parser, with: .invalidResponseValue)
            return
        }

        elementStack.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentText.removeAll(keepingCapacity: true) }

        guard let currentElement = elementStack.last,
              currentElement == Element(
                  name: elementName,
                  namespace: namespaceURI ?? ""
              ) else {
            fail(parser, with: .invalidResponseValue)
            return
        }
        let parent = elementStack.dropLast().last
        switch elementName {
        case "CurrentVolume":
            guard parent == Element(
                name: operation.actionName + "Response",
                namespace: UPnPMediaTargetRenderingControlSOAPCodec.serviceType
            ) else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            guard let parsed = UInt16(value) else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            currentVolume = parsed
        case "CurrentMute":
            guard parent == Element(
                name: operation.actionName + "Response",
                namespace: UPnPMediaTargetRenderingControlSOAPCodec.serviceType
            ) else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            guard let parsed = Self.parseSOAPBool(value) else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            currentMute = parsed
        case "errorCode":
            guard parent == Element(
                name: "UPnPError",
                namespace: Self.upnpControlNamespace
            ), faultCode == nil, let parsed = UInt16(value) else {
                fail(parser, with: .invalidResponseValue)
                return
            }
            faultCode = parsed
        default:
            if isStructuralElement(currentElement), !value.isEmpty {
                fail(parser, with: .invalidResponseValue)
                return
            }
        }

        _ = elementStack.popLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = .malformedXML
        }
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        fail(parser, with: .forbiddenMarkup)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        fail(parser, with: .forbiddenMarkup)
    }

    private func fail(_ parser: XMLParser, with error: UPnPMediaTargetError) {
        self.error = error
        parser.abortParsing()
    }

    private static func parseSOAPBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "1", "true":
            return true
        case "0", "false":
            return false
        default:
            return nil
        }
    }

    private func isExpectedValueElement(_ element: Element) -> Bool {
        guard element.namespace.isEmpty else {
            return false
        }
        switch operation {
        case .getVolume:
            return element.name == "CurrentVolume"
        case .getMute:
            return element.name == "CurrentMute"
        case .setVolume, .setMute:
            return false
        }
    }

    private func isStructuralElement(_ element: Element) -> Bool {
        if element.namespace == Self.soapEnvelopeNamespace {
            return ["Envelope", "Body", "Fault"].contains(element.name)
        }
        if element.namespace == UPnPMediaTargetRenderingControlSOAPCodec.serviceType {
            return element.name == operation.actionName + "Response"
        }
        if element.namespace == Self.upnpControlNamespace {
            return element.name == "UPnPError"
        }
        return element.namespace.isEmpty && element.name == "detail"
    }
}
