import Foundation
import Testing
import MediaControlCore
@testable import UPnPMediaTarget

@Suite("UPnP device description parser")
struct UPnPMediaTargetParserTests {
    @Test("Happy path extracts stable identity and exact RenderingControl URL")
    func happyPath() throws {
        let location = makeHTTPURL(octets: [192, 168, 100, 10], path: "/description.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:happy-path",
            urlBase: nil,
            controlURL: "/upnp/control/rendering"
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(descriptor.identity == MediaTargetIdentity(stableIdentifier: "uuid:happy-path"))
        #expect(descriptor.renderingControlURL == makeHTTPURL(octets: [192, 168, 100, 10], path: "/upnp/control/rendering"))
    }

    @Test("Missing identity fails closed")
    func missingIdentityFailsClosed() {
        let xml = makeDescriptionXML(
            udn: nil,
            urlBase: nil,
            controlURL: "/upnp/control/rendering"
        )
        let location = makeHTTPURL(octets: [192, 168, 100, 10], path: "/description.xml")

        #expect(throws: UPnPMediaTargetError.missingStableIdentity) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(xml, location: location)
        }
    }

    @Test("Missing RenderingControl service fails closed")
    func missingServiceFailsClosed() {
        let xml = makeDescriptionXMLWithoutRenderingControl(
            udn: "uuid:service-missing"
        )

        #expect(throws: UPnPMediaTargetError.missingRenderingControlService) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(xml)
        }
    }

    @Test("Malformed and oversized XML fail closed")
    func malformedAndOversizedXMLFailClosed() {
        let malformed = Data("<root><device>".utf8)

        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(malformed)
        }

        let oversized = Data(repeating: 0x41, count: UPnPMediaTargetDeviceDescriptionParser.defaultMaximumPayloadBytes + 1)

        #expect(throws: UPnPMediaTargetError.oversizedPayload) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(oversized)
        }
    }

    @Test("DTD and entity declarations are rejected, including UTF-16 null-separated markers")
    func forbiddenMarkupIsRejected() {
        let doctype = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE root [<!ENTITY xxe SYSTEM "urn:ignored">]>
            <root/>
            """.utf8
        )

        #expect(throws: UPnPMediaTargetError.forbiddenMarkup) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(doctype)
        }

        let utf16Entity = """
        <?xml version="1.0" encoding="utf-16"?>
        <root>
          <device>
            &xxe;
          </device>
        </root>
        """.data(using: .utf16LittleEndian)!

        let payload = utf16Entity + Data("\u{0000}<\u{0000}!\u{0000}E\u{0000}N\u{0000}T\u{0000}I\u{0000}T\u{0000}Y".utf8)

        #expect(throws: UPnPMediaTargetError.forbiddenMarkup) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(payload)
        }

        let mixedCase = Data("<!DoCtYpE root><root/>".utf8)
        #expect(throws: UPnPMediaTargetError.forbiddenMarkup) {
            try UPnPMediaTargetDeviceDescriptionParser.parse(mixedCase)
        }
    }

    @Test("URLBase takes precedence over LOCATION for relative control URLs")
    func urlBaseTakesPrecedence() throws {
        let location = makeHTTPURL(octets: [192, 168, 50, 10], path: "/description.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:urlbase-precedence",
            urlBase: makeHTTPURL(octets: [192, 168, 50, 20], path: "/root/").absoluteString,
            controlURL: "rendering/control"
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(descriptor.renderingControlURL == makeHTTPURL(octets: [192, 168, 50, 20], path: "/root/rendering/control"))
    }

    @Test("Safe location fallback is used when URLBase is absent")
    func locationFallbackIsUsed() throws {
        let location = makeHTTPURL(octets: [172, 20, 8, 9], path: "/device.xml")
        let xml = makeDescriptionXML(
            udn: "uuid:location-fallback",
            urlBase: nil,
            controlURL: "rendering/control"
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(descriptor.renderingControlURL == makeHTTPURL(octets: [172, 20, 8, 9], path: "/rendering/control"))
    }

    @Test("Namespaced device descriptions use local element names")
    func namespacedDescriptionParses() throws {
        let location = makeHTTPURL(octets: [10, 1, 2, 3], path: "/device.xml")
        let xml = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <u:root xmlns:u="urn:schemas-upnp-org:device-1-0">
              <u:device>
                <u:UDN>uuid:namespaced</u:UDN>
                <u:serviceList>
                  <u:service>
                    <u:serviceType>urn:schemas-upnp-org:service:RenderingControl:1</u:serviceType>
                    <u:controlURL>/rendering/control</u:controlURL>
                  </u:service>
                </u:serviceList>
              </u:device>
            </u:root>
            """.utf8
        )

        let descriptor = try UPnPMediaTargetDeviceDescriptionParser.parse(
            xml,
            location: location
        )

        #expect(descriptor.identity == MediaTargetIdentity(stableIdentifier: "uuid:namespaced"))
    }
}

private func makeHTTPURL(octets: [Int], path: String) -> URL {
    precondition(octets.count == 4)
    let host = octets.map(String.init).joined(separator: ".")
    return URL(string: "http://\(host)\(path)")!
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

private func makeDescriptionXMLWithoutRenderingControl(udn: String) -> Data {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <root>
      <device>
        <UDN>\(udn)</UDN>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
            <controlURL>/upnp/control/ignored</controlURL>
          </service>
        </serviceList>
      </device>
    </root>
    """

    return Data(xml.utf8)
}
