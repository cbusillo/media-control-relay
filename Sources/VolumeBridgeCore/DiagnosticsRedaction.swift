import Foundation

public enum DiagnosticsRedaction {
    public static let redactedValue = "<redacted>"

    private static let sensitiveWords = [
        "address",
        "authorization",
        "credential",
        "identifier",
        "host",
        "ip",
        "key",
        "mac",
        "pairing",
        "password",
        "response",
        "secret",
        "server",
        "serial",
        "ssid",
        "token",
        "uuid",
    ]

    private static let sensitiveNames = [
        "device_uuid",
        "device_id",
        "client_id",
        "session_id",
        "session_key",
    ]

    public static func allowlisted(
        fields: [String: String],
        allowedFieldNames: Set<String>
    ) -> [String: String] {
        fields.filter { allowedFieldNames.contains($0.key) }
    }

    public static func redact(fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { result, entry in
            result[entry.key] = isSensitive(entry.key)
                ? redactedValue
                : entry.value
        }
    }

    public static func redact(_ text: String, sensitiveValues: [String]) -> String {
        sensitiveValues
            .filter { !$0.isEmpty }
            .reduce(text) { partialResult, value in
                partialResult.replacingOccurrences(
                    of: value,
                    with: redactedValue,
                    options: [.caseInsensitive]
                )
            }
    }

    private static func isSensitive(_ fieldName: String) -> Bool {
        let normalized = fieldName
            .replacingOccurrences(
                of: "([A-Z]+)([A-Z][a-z])",
                with: "$1_$2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1_$2",
                options: .regularExpression
            )
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let words = normalized.split(separator: "_").map(String.init)
        return sensitiveNames.contains {
            normalized == $0 || normalized.hasSuffix("_\($0)")
        } ||
            sensitiveWords.contains { words.contains($0) }
    }
}
