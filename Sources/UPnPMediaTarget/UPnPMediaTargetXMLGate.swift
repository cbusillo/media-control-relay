import Foundation

enum UPnPMediaTargetXMLGate {
    static let defaultMaximumPayloadBytes = 64 * 1024

    static func validatePayload(
        _ data: Data,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws(UPnPMediaTargetError) {
        guard maximumPayloadBytes > 0, data.count <= maximumPayloadBytes else {
            throw .oversizedPayload
        }

        guard !containsForbiddenMarkup(data) else {
            throw .forbiddenMarkup
        }
    }

    static func makeParser(
        data: Data,
        delegate: XMLParserDelegate
    ) -> XMLParser {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        return parser
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
