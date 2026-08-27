import Foundation

public enum UPnPMediaTargetSCPDParser {
    public static let defaultMaximumPayloadBytes = 128 * 1024
    static let defaultMaximumDepth = 64
    static let defaultMaximumStateVariableCount = 128

    public static func parse(
        _ data: Data,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) -> UPnPMediaTargetVolumeCapability {
        try UPnPMediaTargetXMLGate.validatePayload(
            data,
            maximumPayloadBytes: maximumPayloadBytes
        )

        let delegate = SCPDDelegate()
        let parser = UPnPMediaTargetXMLGate.makeParser(data: data, delegate: delegate)
        guard parser.parse() else {
            throw delegate.error ?? .malformedXML
        }

        guard let capture = delegate.volumeCapture else {
            throw .missingVolumeCapability
        }
        guard capture.dataType == "ui2" else {
            throw .invalidVolumeCapability
        }
        guard capture.allowedValueRangeFound,
              let maximum = capture.maximum else {
            throw .missingVolumeCapability
        }
        guard capture.allowedValueRangeCount == 1 else {
            throw .invalidVolumeCapability
        }
        let minimum = capture.minimum ?? 0
        let step = capture.step ?? 1

        return try UPnPMediaTargetVolumeCapability(
            minimumVolume: minimum,
            maximumVolume: maximum,
            step: step
        )
    }
}

private final class SCPDDelegate: NSObject, XMLParserDelegate {
    final class StateVariableCapture {
        var name: String?
        var dataType: String?
        var allowedValueRangeFound = false
        var minimum: Int?
        var maximum: Int?
        var step: Int?
        var allowedValueRangeCount = 0
        var duplicateField = false
    }

    var volumeCapture: StateVariableCapture?
    var error: UPnPMediaTargetError?

    private var elementStack: [String] = []
    private var textStack: [String] = []
    private var currentStateVariable: StateVariableCapture?
    private var depth = 0
    private var stateVariableCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        depth += 1
        guard depth <= UPnPMediaTargetSCPDParser.defaultMaximumDepth else {
            fail(.malformedXML, parser: parser)
            return
        }
        elementStack.append(elementName)
        textStack.append("")

        if elementName == "stateVariable" {
            stateVariableCount += 1
            guard stateVariableCount <= UPnPMediaTargetSCPDParser.defaultMaximumStateVariableCount else {
                fail(.malformedXML, parser: parser)
                return
            }
            guard currentStateVariable == nil else {
                fail(.invalidVolumeCapability, parser: parser)
                return
            }
            if elementStack.dropLast().last == "serviceStateTable" {
                currentStateVariable = StateVariableCapture()
            }
        } else if elementName == "allowedValueRange",
                  currentStateVariable != nil,
                  elementStack.dropLast().last == "stateVariable" {
            currentStateVariable?.allowedValueRangeCount += 1
            currentStateVariable?.allowedValueRangeFound = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else {
            fail(.malformedXML, parser: parser)
            return
        }
        textStack[textStack.count - 1].append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let currentElement = elementStack.popLast(),
              currentElement == elementName,
              let text = textStack.popLast() else {
            fail(.malformedXML, parser: parser)
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.last

        if let capture = currentStateVariable {
            switch (elementName, parent) {
            case ("name", "stateVariable"):
                guard capture.name == nil else {
                    capture.duplicateField = true
                    break
                }
                capture.name = value
            case ("dataType", "stateVariable"):
                guard capture.dataType == nil else {
                    capture.duplicateField = true
                    break
                }
                capture.dataType = value
            case ("minimum", "allowedValueRange"):
                assignRangeInteger(
                    value,
                    to: &capture.minimum,
                    capture: capture
                )
            case ("maximum", "allowedValueRange"):
                assignRangeInteger(
                    value,
                    to: &capture.maximum,
                    capture: capture
                )
            case ("step", "allowedValueRange"):
                assignRangeInteger(
                    value,
                    to: &capture.step,
                    capture: capture
                )
            default:
                break
            }

            if elementName == "stateVariable", parent == "serviceStateTable" {
                guard capture.name != "Volume" || volumeCapture == nil else {
                    fail(.invalidVolumeCapability, parser: parser)
                    return
                }
                if capture.name == "Volume" {
                    guard !capture.duplicateField else {
                        fail(.invalidVolumeCapability, parser: parser)
                        return
                    }
                    volumeCapture = capture
                }
                currentStateVariable = nil
            }
        }
        depth -= 1
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
        fail(.forbiddenMarkup, parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        fail(.forbiddenMarkup, parser: parser)
    }

    private func assignRangeInteger(
        _ value: String,
        to field: inout Int?,
        capture: StateVariableCapture
    ) {
        guard elementStack.dropLast().last == "stateVariable",
              field == nil,
              !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) }),
              let integer = Int(value) else {
            capture.duplicateField = true
            return
        }
        field = integer
    }

    private func fail(
        _ error: UPnPMediaTargetError,
        parser: XMLParser
    ) {
        if self.error == nil {
            self.error = error
        }
        parser.abortParsing()
    }
}
