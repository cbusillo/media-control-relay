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
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetDeviceDescription {
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
            if delegate.renderingControlControlURLFound {
                throw .missingRenderingControlSCPDURL
            }
            throw .missingRenderingControlControlURL
        }
        guard let renderingControlSCPDText = delegate.renderingControlSCPDURL else {
            throw .missingRenderingControlSCPDURL
        }

        let renderingControlURL = try UPnPMediaTargetEndpointPolicy.resolveControlURL(
            renderingControlControlURL,
            relativeTo: baseURL
        )
        let renderingControlSCPDURL = try UPnPMediaTargetEndpointPolicy.resolveControlURL(
            renderingControlSCPDText,
            relativeTo: baseURL
        )

        return UPnPMediaTargetDeviceDescription(
            identity: identity,
            renderingControlURL: renderingControlURL,
            renderingControlSCPDURL: renderingControlSCPDURL
        )
    }

}

private final class DeviceDescriptionDelegate: NSObject, XMLParserDelegate {
    var stableIdentifier: String?
    var urlBase: String?
    var urlBaseElementFound = false
    var renderingControlControlURL: String?
    var renderingControlSCPDURL: String?
    var renderingControlControlURLFound = false
    var renderingControlServiceFound = false
    var error: UPnPMediaTargetError?

    private struct ServiceCapture {
        var serviceType: String?
        var controlURL: String?
        var scpdURL: String?
    }

    private var currentText = ""
    private var elementStack: [String] = []
    private var serviceStack: [ServiceCapture] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentText.removeAll(keepingCapacity: true)
        elementStack.append(elementName)
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
        guard elementStack.last == elementName else {
            error = .malformedXML
            parser.abortParsing()
            return
        }
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.dropLast().last
        defer {
            currentText.removeAll(keepingCapacity: true)
            elementStack.removeLast()
        }

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
            if parent == "service", !serviceStack.isEmpty {
                assignServiceField(
                    value,
                    to: &serviceStack[serviceStack.count - 1].serviceType,
                    parser: parser
                )
            }
        case "controlURL":
            if parent == "service", !serviceStack.isEmpty {
                assignServiceField(
                    value,
                    to: &serviceStack[serviceStack.count - 1].controlURL,
                    parser: parser
                )
            }
        case "SCPDURL":
            if parent == "service", !serviceStack.isEmpty {
                assignServiceField(
                    value,
                    to: &serviceStack[serviceStack.count - 1].scpdURL,
                    parser: parser
                )
            }
        case "service":
            if let service = serviceStack.popLast(),
               service.serviceType == UPnPMediaTargetDeviceDescriptionParser.renderingControlServiceType {
                renderingControlServiceFound = true
                let controlURL = service.controlURL.flatMap { value in
                    value.isEmpty ? nil : value
                }
                let scpdURL = service.scpdURL.flatMap { value in
                    value.isEmpty ? nil : value
                }
                if controlURL != nil {
                    renderingControlControlURLFound = true
                }
                if renderingControlControlURL == nil,
                   renderingControlSCPDURL == nil,
                   let controlURL,
                   let scpdURL {
                    renderingControlControlURL = controlURL
                    renderingControlSCPDURL = scpdURL
                }
            }
        default:
            break
        }
    }

    private func assignServiceField(
        _ value: String,
        to field: inout String?,
        parser: XMLParser
    ) {
        guard field == nil else {
            error = .malformedXML
            parser.abortParsing()
            return
        }
        field = value
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
