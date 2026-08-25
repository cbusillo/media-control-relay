import Foundation

public enum UPnPMediaTargetEndpointPolicy {
    public static let maximumURLBytes = 2 * 1024
    public static let maximumPathBytes = 1024

    private static let allowedPortRange = 1...65535

    public static func validate(_ url: URL) throws(UPnPMediaTargetError) -> URL {
        guard url.absoluteString.utf8.count <= maximumURLBytes else {
            throw .oversizedURL
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw .invalidControlURL
        }

        guard components.scheme?.lowercased() == "http" else {
            throw .unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw .userInfoPresent
        }
        guard components.fragment == nil else {
            throw .fragmentPresent
        }
        guard components.percentEncodedPath.utf8.count <= maximumPathBytes else {
            throw .oversizedURL
        }
        if let port = components.port {
            guard allowedPortRange.contains(port) else {
                throw .invalidPort
            }
        }

        guard let host = components.host, isAllowedHost(host) else {
            throw .unsafeHost
        }

        guard let canonicalURL = components.url else {
            throw .invalidControlURL
        }
        return canonicalURL
    }

    static func validatedBaseURL(
        from text: String?
    ) throws(UPnPMediaTargetError) -> URL? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil else {
            throw .invalidControlURL
        }
        return try validate(url)
    }

    static func resolveControlURL(
        _ text: String,
        relativeTo baseURL: URL?
    ) throws(UPnPMediaTargetError) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .missingRenderingControlControlURL
        }

        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return try validate(absoluteURL)
        }

        guard let baseURL else {
            throw .invalidControlURL
        }

        guard let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            throw .invalidControlURL
        }

        return try validate(resolved)
    }

    static func isAllowedHost(_ host: String) -> Bool {
        guard let octets = IPv4AddressParser.octets(from: host) else {
            return false
        }

        return isAllowedIPv4Octets(octets)
    }

    static func isAllowedIPv4Octets(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else {
            return false
        }
        switch octets[0] {
        case 10:
            return true
        case 172:
            return (16...31).contains(octets[1])
        case 169:
            return octets[1] == 254
        case 192:
            return octets[1] == 168
        default:
            return false
        }
    }
}

private enum IPv4AddressParser {
    static func octets(from host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        for part in parts {
            guard !part.isEmpty, part.count <= 3 else {
                return nil
            }
            guard part.count == 1 || part.first != "0" else {
                return nil
            }
            guard let value = UInt16(part), value <= 255 else {
                return nil
            }
            octets.append(UInt8(value))
        }

        return octets
    }
}
