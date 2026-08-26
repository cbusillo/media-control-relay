import Foundation
import MediaControlCore

public enum UPnPMediaTargetDeviceDescriptionParser {
    public static let defaultMaximumPayloadBytes = UPnPMediaTargetXMLGate.defaultMaximumPayloadBytes
    static let renderingControlServiceType =
        "urn:schemas-upnp-org:service:RenderingControl:1"

    public static func parse(
        _ data: Data,
        location: URL? = nil,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetDescriptor {
        try UPnPMediaTargetXMLGate.validatePayload(
            data,
            maximumPayloadBytes: maximumPayloadBytes
        )

        let delegate = DeviceDescriptionDelegate()
        let parser = UPnPMediaTargetXMLGate.makeParser(data: data, delegate: delegate)

        guard parser.parse() else {
            throw delegate.error ?? .malformedXML
        }

        guard let stableIdentifier = delegate.stableIdentifier,
              let identity = UPnPMediaTargetIdentityParser.parse(
                  stableIdentifier
              ) else {
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
            identity: identity,
            renderingControlURL: renderingControlURL
        )
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
