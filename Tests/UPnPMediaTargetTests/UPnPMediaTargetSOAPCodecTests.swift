import Foundation
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP RenderingControl SOAP codec")
struct UPnPMediaTargetSOAPCodecTests {
    private let codec = UPnPMediaTargetRenderingControlSOAPCodec()

    @Test("Requests use exact RenderingControl actions and fields")
    func requestEncoding() throws {
        let endpoint = makeSOAPTestEndpoint()

        let getVolume = try codec.makeRequest(
            endpoint: endpoint,
            operation: .getVolume
        )
        let setVolume = try codec.makeRequest(
            endpoint: endpoint,
            operation: .setVolume(42)
        )
        let setMute = try codec.makeRequest(
            endpoint: endpoint,
            operation: .setMute(true)
        )

        #expect(getVolume.httpMethod == "POST")
        #expect(getVolume.url == endpoint)
        #expect(
            getVolume.value(forHTTPHeaderField: "SOAPAction") ==
                "\"urn:schemas-upnp-org:service:RenderingControl:1#GetVolume\""
        )
        #expect(requestBody(getVolume).contains("<u:GetVolume"))
        #expect(requestBody(getVolume).contains("<InstanceID>0</InstanceID>"))
        #expect(requestBody(getVolume).contains("<Channel>Master</Channel>"))
        #expect(requestBody(setVolume).contains("<DesiredVolume>42</DesiredVolume>"))
        #expect(requestBody(setMute).contains("<DesiredMute>1</DesiredMute>"))
    }

    @Test("Requests reject unsafe endpoints and invalid volume values")
    func requestValidation() {
        #expect(throws: UPnPMediaTargetError.unsafeHost) {
            try codec.makeRequest(
                endpoint: URL(string: "http://public.example/control")!,
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidRequestValue) {
            try codec.makeRequest(
                endpoint: makeSOAPTestEndpoint(),
                operation: .setVolume(65_536)
            )
        }
    }

    @Test("Get responses decode bounded volume and mute values")
    func getResponseDecoding() throws {
        let volume = try codec.decodeResponse(
            responseXML(action: "GetVolume", field: "CurrentVolume", value: "37"),
            operation: .getVolume
        )
        let mute = try codec.decodeResponse(
            responseXML(action: "GetMute", field: "CurrentMute", value: "true"),
            operation: .getMute
        )

        #expect(volume == .volume(37))
        #expect(mute == .mute(true))
    }

    @Test("Set responses require exact acknowledgement bodies")
    func setResponseDecoding() throws {
        #expect(
            try codec.decodeResponse(
                responseXML(action: "SetMute", field: nil, value: nil),
                operation: .setMute(false)
            ) == .acknowledged
        )
    }

    @Test("UPnP faults expose only the numeric fault code")
    func faultDecoding() throws {
        let response = try codec.decodeResponse(
            faultXML(code: 701, description: "private device text"),
            operation: .setVolume(20)
        )

        #expect(
            response == .fault(
                UPnPMediaTargetRenderingControlFault(code: 701)
            )
        )
    }

    @Test("Malformed, wrong-action, unsafe, and invalid values fail closed")
    func invalidResponsesFailClosed() {
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                responseXML(action: "GetMute", field: "CurrentMute", value: "0"),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try codec.decodeResponse(
                responseXML(
                    action: "GetVolume",
                    field: "CurrentVolume",
                    value: "25"
                ) + responseXML(
                    action: "GetVolume",
                    field: "CurrentVolume",
                    value: "26"
                ),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                Data(
                    """
                    <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                      <CurrentVolume>25</CurrentVolume>
                    </u:GetVolumeResponse>
                    """.utf8
                ),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                Data(
                    """
                    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                      <s:Body>
                        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                          unexpected<CurrentVolume>25</CurrentVolume>
                        </u:GetVolumeResponse>
                      </s:Body>
                    </s:Envelope>
                    """.utf8
                ),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                Data(
                    """
                    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                      <s:Body>
                        <u:SetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                          unexpected
                        </u:SetMuteResponse>
                      </s:Body>
                    </s:Envelope>
                    """.utf8
                ),
                operation: .setMute(false)
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                Data(
                    """
                    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                      <s:Body>
                        <s:Fault>
                          <detail><wrapper><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>501</errorCode></UPnPError></wrapper></detail>
                        </s:Fault>
                      </s:Body>
                    </s:Envelope>
                    """.utf8
                ),
                operation: .setMute(false)
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                Data(
                    """
                    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
                      <s:Body>
                        <s:Fault><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>501</errorCode><errorCode>502</errorCode></UPnPError></detail></s:Fault>
                      </s:Body>
                    </s:Envelope>
                    """.utf8
                ),
                operation: .setMute(false)
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(
                responseXML(action: "GetVolume", field: "CurrentVolume", value: "65536"),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try codec.decodeResponse(Data(), operation: .setMute(false))
        }
        #expect(throws: UPnPMediaTargetError.forbiddenMarkup) {
            try codec.decodeResponse(
                Data("<!DOCTYPE x [<!ENTITY y SYSTEM 'urn:test'>]><x/>".utf8),
                operation: .getVolume
            )
        }
        #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            try codec.decodeResponse(Data("<broken>".utf8), operation: .getMute)
        }
        #expect(throws: UPnPMediaTargetError.oversizedPayload) {
            try codec.decodeResponse(
                Data(repeating: 0x41, count: 17),
                operation: .getVolume,
                maximumPayloadBytes: 16
            )
        }
    }
}

private func requestBody(_ request: URLRequest) -> String {
    String(decoding: request.httpBody ?? Data(), as: UTF8.self)
}

private func makeSOAPTestEndpoint() -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = [10, 23, 45, 67].map(String.init).joined(separator: ".")
    components.path = "/rendering/control"
    return components.url!
}

private func responseXML(
    action: String,
    field: String?,
    value: String?
) -> Data {
    let responseField: String
    if let field, let value {
        responseField = "<\(field)>\(value)</\(field)>"
    } else {
        responseField = ""
    }
    return Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:\(action)Response xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              \(responseField)
            </u:\(action)Response>
          </s:Body>
        </s:Envelope>
        """.utf8
    )
}

private func faultXML(code: UInt16, description: String) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <s:Fault>
              <detail>
                <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                  <errorCode>\(code)</errorCode>
                  <errorDescription>\(description)</errorDescription>
                </UPnPError>
              </detail>
            </s:Fault>
          </s:Body>
        </s:Envelope>
        """.utf8
    )
}
