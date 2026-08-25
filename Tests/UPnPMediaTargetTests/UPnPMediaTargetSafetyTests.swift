import Foundation
import Testing
import MediaControlCore
@testable import UPnPMediaTarget

@Suite("UPnP endpoint safety")
struct UPnPMediaTargetSafetyTests {
    @Test("RFC1918 and link-local IPv4 literals are accepted")
    func acceptsLocalIPv4Literals() throws {
        for octets in [[10, 1, 2, 3], [172, 16, 1, 2], [192, 168, 10, 20], [169, 254, 4, 5]] {
            let url = makeHTTPURL(octets: octets, path: "/description.xml")
            let validated = try UPnPMediaTargetEndpointPolicy.validate(url)
            #expect(validated == url)
        }
    }

    @Test("Only canonical private and link-local IPv4 octets are accepted")
    func addressClassesAreExplicit() {
        #expect(UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([10, 0, 0, 1]))
        #expect(UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([172, 31, 0, 1]))
        #expect(UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([192, 168, 0, 1]))
        #expect(UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([169, 254, 0, 1]))
        #expect(!UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([127, 0, 0, 1]))
        #expect(!UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([172, 32, 0, 1]))
        #expect(!UPnPMediaTargetEndpointPolicy.isAllowedIPv4Octets([192, 0, 2, 1]))
    }

    @Test("Unsafe endpoint components are rejected")
    func rejectsUnsafeComponents() {
        let base = makeHTTPURL(octets: [10, 0, 0, 1], path: "/description.xml")

        #expect(throws: UPnPMediaTargetError.unsupportedScheme) {
            try UPnPMediaTargetEndpointPolicy.validate(URL(string: base.absoluteString.replacingOccurrences(of: "http://", with: "https://"))!)
        }

        #expect(throws: UPnPMediaTargetError.userInfoPresent) {
            try UPnPMediaTargetEndpointPolicy.validate(
                makeHTTPURL(octets: [10, 0, 0, 1], path: "/description.xml", userInfo: "user:pass")
            )
        }

        #expect(throws: UPnPMediaTargetError.fragmentPresent) {
            try UPnPMediaTargetEndpointPolicy.validate(
                URL(string: base.absoluteString + "#fragment")!
            )
        }

        #expect(throws: UPnPMediaTargetError.invalidPort) {
            try UPnPMediaTargetEndpointPolicy.validate(
                makeHTTPURL(octets: [10, 0, 0, 1], path: "/description.xml", port: 70000)
            )
        }

        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try UPnPMediaTargetEndpointPolicy.validate(
                URL(string: "http://public.example/description.xml")!
            )
        }

        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try UPnPMediaTargetEndpointPolicy.validate(
                URL(string: "http://010.0.0.1/description.xml")!
            )
        }

        let oversizedPath = "/" + String(repeating: "a", count: UPnPMediaTargetEndpointPolicy.maximumPathBytes + 1)
        #expect(throws: UPnPMediaTargetError.oversizedURL) {
            try UPnPMediaTargetEndpointPolicy.validate(
                makeHTTPURL(octets: [10, 0, 0, 1], path: oversizedPath)
            )
        }
    }

    @Test("Relative control URLs resolve against safe URLBase or LOCATION")
    func resolvesRelativeControlURLsAgainstSafeBases() throws {
        let location = makeHTTPURL(octets: [192, 168, 1, 44], path: "/root/device.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:stable-identity-1",
            urlBase: makeHTTPURL(octets: [192, 168, 1, 99], path: "/media/").absoluteString,
            controlURL: "rendering/control"
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(descriptor.identity == MediaTargetIdentity(stableIdentifier: "uuid:stable-identity-1"))
        #expect(
            descriptor.renderingControlURL == makeHTTPURL(
                octets: [192, 168, 1, 99],
                path: "/media/rendering/control"
            )
        )
    }

    @Test("LOCATION is used when URLBase is absent")
    func locationResolvesRelativeControlURLs() throws {
        let location = makeHTTPURL(octets: [172, 16, 4, 9], path: "/device/description.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:stable-identity-2",
            urlBase: nil,
            controlURL: "/upnp/control/rendering"
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(
            descriptor.renderingControlURL == makeHTTPURL(
                octets: [172, 16, 4, 9],
                path: "/upnp/control/rendering"
            )
        )
    }

    @Test("A stable identity survives endpoint changes")
    func stableIdentitySurvivesEndpointChanges() throws {
        let xmlA = makeDescriptionXML(
            udn: "uuid:stable-identity-3",
            urlBase: makeHTTPURL(octets: [10, 0, 0, 8], path: "/").absoluteString,
            controlURL: "rendering/control"
        )
        let xmlB = makeDescriptionXML(
            udn: "uuid:stable-identity-3",
            urlBase: makeHTTPURL(octets: [10, 0, 0, 9], path: "/").absoluteString,
            controlURL: "rendering/control"
        )

        let descriptorA = try UPnPMediaTargetDeviceDescriptionParser.parse(xmlA)
        let descriptorB = try UPnPMediaTargetDeviceDescriptionParser.parse(xmlB)

        #expect(descriptorA.identity == descriptorB.identity)
        #expect(descriptorA.renderingControlURL != descriptorB.renderingControlURL)
    }

    @Test("Unsafe URLBase fails closed instead of falling back to LOCATION")
    func unsafeURLBaseFailsClosed() {
        let location = makeHTTPURL(octets: [10, 0, 0, 1], path: "/description.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:unsafe-base",
            urlBase: "http://public.example/root/",
            controlURL: "rendering/control"
        )

        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(xml, location: location)
        }
    }

    @Test("Unsafe LOCATION is rejected even when URLBase is safe")
    func unsafeLocationFailsClosed() {
        let xml = makeDescriptionXML(
            udn: "uuid:unsafe-location",
            urlBase: makeHTTPURL(octets: [10, 0, 0, 2], path: "/root/").absoluteString,
            controlURL: "rendering/control"
        )

        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(
                xml,
                location: URL(string: "http://public.example/description.xml")!
            )
        }
    }

    @Test("A present but blank URLBase is malformed")
    func blankURLBaseFailsClosed() {
        let location = makeHTTPURL(octets: [10, 0, 0, 1], path: "/description.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:blank-base",
            urlBase: "   ",
            controlURL: "rendering/control"
        )

        #expect(throws: UPnPMediaTargetError.invalidControlURL) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(xml, location: location)
        }
    }
}

private func makeHTTPURL(
    octets: [Int],
    path: String,
    userInfo: String? = nil,
    port: Int? = nil
) -> URL {
    precondition(octets.count == 4)
    var components = URLComponents()
    components.scheme = "http"
    components.host = octets.map(String.init).joined(separator: ".")
    components.path = path
    if let userInfo {
        let parts = userInfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        components.user = String(parts.first ?? "")
        if parts.count > 1 {
            components.password = String(parts[1])
        }
    }
    components.port = port
    return components.url!
}

private func makeDescriptionXML(
    udn: String?,
    urlBase: String?,
    controlURL: String?
) -> Data {
    var xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <root>
      <device>
    """

    if let udn {
        xml += "\n        <UDN>\(udn)</UDN>"
    }

    if let urlBase {
        xml += "\n        <URLBase>\(urlBase)</URLBase>"
    }

    xml += """

        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
    """

    if let controlURL {
        xml += "\n            <controlURL>\(controlURL)</controlURL>"
    }

    xml += """

          </service>
        </serviceList>
      </device>
    </root>
    """

    return Data(xml.utf8)
}
