import Foundation
import MediaControlCore

public enum UPnPMediaTargetDeviceDescriptionParser {
    public static let defaultMaximumPayloadBytes = 64 * 1024
    static let renderingControlServiceType =
        "urn:schemas-upnp-org:service:RenderingControl:1"

    public static func parse(
        _ data: Data,
        location: URL? = nil,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        guard maximumPayloadBytes > 0, data.count <= maximumPayloadBytes else {
            throw .oversizedPayload
        }

        guard !containsForbiddenMarkup(data) else {
            throw .forbiddenMarkup
        }

        let delegate = DeviceDescriptionDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate

        guard parser.parse() else {
            throw delegate.error ?? .malformedXML
        }

        guard let stableIdentifier = delegate.stableIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !stableIdentifier.isEmpty else {
            throw .missingStableIdentity
        }

        let validatedLocation: URL?
        if let location {
            validatedLocation = try UPnPMediaTargetEndpointPolicy.validate(location)
        } else {
            validatedLocation = nil
        }
        let baseURL: URL?
        if delegate.urlBaseElementFound {
            baseURL = try UPnPMediaTargetEndpointPolicy.validatedBaseURL(
                from: delegate.urlBase
            )
        } else {
            baseURL = validatedLocation
        }

        guard delegate.renderingControlServiceFound else {
            throw .missingRenderingControlService
        }

        guard let renderingControlControlURL = delegate.renderingControlControlURL else {
            throw .missingRenderingControlControlURL
        }

        let renderingControlURL = try UPnPMediaTargetEndpointPolicy.resolveControlURL(
            renderingControlControlURL,
            relativeTo: baseURL
        )

        return UPnPMediaTargetDescriptor(
            identity: MediaTargetIdentity(stableIdentifier: stableIdentifier),
            renderingControlURL: renderingControlURL
        )
    }

    private static func containsForbiddenMarkup(_ data: Data) -> Bool {
        let normalized = Data(data.lazy.compactMap { byte -> UInt8? in
            guard byte != 0 else {
                return nil
            }
            if (97...122).contains(byte) {
                return byte - 32
            }
            return byte
        })
        return containsASCIISequence(normalized, ascii: [60, 33, 68, 79, 67, 84, 89, 80, 69])
            || containsASCIISequence(normalized, ascii: [60, 33, 69, 78, 84, 73, 84, 89])
    }

    private static func containsASCIISequence(_ data: Data, ascii: [UInt8]) -> Bool {
        guard data.count >= ascii.count else {
            return false
        }

        let bytes = [UInt8](data)
        let lastStart = bytes.count - ascii.count
        for start in 0...lastStart {
            if bytes[start..<(start + ascii.count)].elementsEqual(ascii) {
                return true
            }
        }
        return false
    }
}

private final class DeviceDescriptionDelegate: NSObject, XMLParserDelegate {
    var stableIdentifier: String?
    var urlBase: String?
    var urlBaseElementFound = false
    var renderingControlControlURL: String?
    var renderingControlServiceFound = false
    var error: UPnPMediaTargetError?

    private struct ServiceCapture {
        var serviceType: String?
        var controlURL: String?
    }

    private var currentText = ""
    private var serviceStack: [ServiceCapture] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentText.removeAll(keepingCapacity: true)
        if elementName == "service" {
            serviceStack.append(ServiceCapture())
        }
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

        switch elementName {
        case "UDN":
            if stableIdentifier == nil, !value.isEmpty {
                stableIdentifier = value
            }
        case "URLBase":
            if !urlBaseElementFound {
                urlBaseElementFound = true
                urlBase = value
            }
        case "serviceType":
            if !serviceStack.isEmpty {
                serviceStack[serviceStack.count - 1].serviceType = value
            }
        case "controlURL":
            if !serviceStack.isEmpty {
                serviceStack[serviceStack.count - 1].controlURL = value
            }
        case "service":
            if let service = serviceStack.popLast(),
               service.serviceType == UPnPMediaTargetDeviceDescriptionParser.renderingControlServiceType {
                renderingControlServiceFound = true
                if renderingControlControlURL == nil,
                   let controlURL = service.controlURL,
                   !controlURL.isEmpty {
                    renderingControlControlURL = controlURL
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = .malformedXML
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        error = .forbiddenMarkup
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        error = .forbiddenMarkup
        parser.abortParsing()
    }
}
