import Foundation
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP HTTP transport", .serialized)
struct UPnPMediaTargetHTTPTransportTests {
    @Test("URLSession transport returns bounded HTTP data")
    func success() async throws {
        FixtureURLProtocol.scenario = .response(
            statusCode: 200,
            headers: [:],
            chunks: [Data("one".utf8), Data("two".utf8)]
        )
        let transport = makeHTTPTransport()
        let (data, response) = try await transport.send(
            URLRequest(url: makeHTTPTestEndpoint()),
            maximumResponseBytes: 16
        )

        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "onetwo")
    }

    @Test("Redirects are rejected without following the new endpoint")
    func redirectRejection() async {
        FixtureURLProtocol.scenario = .redirect(
            URL(string: "http://public.example/redirected")!
        )
        let transport = makeHTTPTransport()

        await #expect(throws: UPnPMediaTargetError.redirectRejected) {
            _ = try await transport.send(
                URLRequest(url: makeHTTPTestEndpoint()),
                maximumResponseBytes: 64
            )
        }
    }

    @Test("Declared and streamed oversized bodies are rejected")
    func responseSizeBounds() async {
        FixtureURLProtocol.scenario = .response(
            statusCode: 200,
            headers: ["Content-Length": "100"],
            chunks: []
        )
        let transport = makeHTTPTransport(maximumResponseBytes: 8)
        await #expect(throws: UPnPMediaTargetError.oversizedPayload) {
            _ = try await transport.send(
                URLRequest(url: makeHTTPTestEndpoint()),
                maximumResponseBytes: 8
            )
        }

        FixtureURLProtocol.scenario = .response(
            statusCode: 200,
            headers: [:],
            chunks: [Data(repeating: 0x41, count: 9)]
        )
        await #expect(throws: UPnPMediaTargetError.oversizedPayload) {
            _ = try await transport.send(
                URLRequest(url: makeHTTPTestEndpoint()),
                maximumResponseBytes: 8
            )
        }
    }

    @Test("Task cancellation maps to the neutral transport cancellation")
    func cancellation() async {
        let requestStart = RequestStartSignal()
        FixtureURLProtocol.scenario = .hanging(requestStart)
        let transport = makeHTTPTransport(timeoutInterval: 5)
        let task = Task {
            try await transport.send(
                URLRequest(url: makeHTTPTestEndpoint()),
                maximumResponseBytes: 64
            )
        }
        await requestStart.wait()
        task.cancel()

        await #expect(throws: UPnPMediaTargetError.cancelled) {
            _ = try await task.value
        }
    }

    @Test("Request timeout maps to the neutral timeout failure")
    func timeout() async {
        FixtureURLProtocol.scenario = .delayed(
            delay: 0.25,
            data: Data("late".utf8)
        )
        let transport = makeHTTPTransport(timeoutInterval: 0.05)

        await #expect(throws: UPnPMediaTargetError.timeout) {
            _ = try await transport.send(
                URLRequest(url: makeHTTPTestEndpoint()),
                maximumResponseBytes: 64
            )
        }
    }

    @Test("RenderingControl transport parses faults and rejects response URL changes")
    func renderingControlHTTPPolicy() async throws {
        let endpoint = makeHTTPTestEndpoint()
        let faultTransport = StubHTTPTransport(
            data: makeHTTPFaultXML(code: 501),
            response: HTTPURLResponse(
                url: endpoint,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let renderingControl = try UPnPMediaTargetRenderingControlTransport(
            endpoint: endpoint,
            http: faultTransport
        )
        #expect(
            try await renderingControl.perform(.setMute(true)) ==
                .fault(UPnPMediaTargetRenderingControlFault(code: 501))
        )

        for statusCode in [204, 401, 404] {
            let statusTransport = StubHTTPTransport(
                data: makeSetMuteResponseXML(),
                response: HTTPURLResponse(
                    url: endpoint,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
            let statusControl = try UPnPMediaTargetRenderingControlTransport(
                endpoint: endpoint,
                http: statusTransport
            )
            await #expect(
                throws: UPnPMediaTargetError.unexpectedStatusCode(statusCode)
            ) {
                _ = try await statusControl.perform(.setMute(false))
            }
        }

        let faultWithSuccessStatus = StubHTTPTransport(
            data: makeHTTPFaultXML(code: 501),
            response: HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let faultWithSuccessControl = try UPnPMediaTargetRenderingControlTransport(
            endpoint: endpoint,
            http: faultWithSuccessStatus
        )
        await #expect(throws: UPnPMediaTargetError.invalidResponseValue) {
            _ = try await faultWithSuccessControl.perform(.setMute(false))
        }

        let changedURLTransport = StubHTTPTransport(
            data: Data(),
            response: HTTPURLResponse(
                url: makeChangedHTTPTestEndpoint(),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let changedURLControl = try UPnPMediaTargetRenderingControlTransport(
            endpoint: endpoint,
            http: changedURLTransport
        )
        await #expect(throws: UPnPMediaTargetError.redirectRejected) {
            _ = try await changedURLControl.perform(.setMute(false))
        }
    }
}

private struct StubHTTPTransport: UPnPMediaTargetHTTPTransacting, @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> (Data, HTTPURLResponse) {
        (data, response)
    }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    enum Scenario {
        case response(statusCode: Int, headers: [String: String], chunks: [Data])
        case redirect(URL)
        case hanging(RequestStartSignal?)
        case delayed(delay: TimeInterval, data: Data)
    }

    nonisolated(unsafe) static var scenario = Scenario.hanging(nil)

    private var delayedWorkItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        switch Self.scenario {
        case let .response(statusCode, headers, chunks):
            send(statusCode: statusCode, headers: headers, chunks: chunks)
        case let .redirect(destination):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": destination.absoluteString]
            )!
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: destination),
                redirectResponse: response
            )
        case let .hanging(requestStart):
            if let requestStart {
                Task {
                    await requestStart.signal()
                }
            }
        case let .delayed(delay, data):
            let workItem = DispatchWorkItem { [weak self] in
                self?.send(statusCode: 200, headers: [:], chunks: [data])
            }
            delayedWorkItem = workItem
            DispatchQueue.global().asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
        }
    }

    override func stopLoading() {
        delayedWorkItem?.cancel()
        delayedWorkItem = nil
    }

    private func send(
        statusCode: Int,
        headers: [String: String],
        chunks: [Data]
    ) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

private actor RequestStartSignal {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func signal() {
        started = true
        continuation?.resume()
        continuation = nil
    }
}

private func makeHTTPTransport(
    timeoutInterval: TimeInterval = 2,
    maximumResponseBytes: Int = 64 * 1024
) -> UPnPMediaTargetURLSessionHTTPTransport {
    UPnPMediaTargetURLSessionHTTPTransport(
        protocolClasses: [FixtureURLProtocol.self],
        timeoutInterval: timeoutInterval,
        maximumResponseBytes: maximumResponseBytes
    )
}

private func makeHTTPTestEndpoint() -> URL {
    makeHTTPTestEndpoint(octets: [10, 54, 32, 10])
}

private func makeChangedHTTPTestEndpoint() -> URL {
    makeHTTPTestEndpoint(octets: [10, 54, 32, 11])
}

private func makeHTTPTestEndpoint(octets: [Int]) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = octets.map(String.init).joined(separator: ".")
    components.path = "/rendering/control"
    return components.url!
}

private func makeHTTPFaultXML(code: UInt16) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <s:Fault>
              <detail>
                <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                  <errorCode>\(code)</errorCode>
                </UPnPError>
              </detail>
            </s:Fault>
          </s:Body>
        </s:Envelope>
        """.utf8
    )
}

private func makeSetMuteResponseXML() -> Data {
    Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1" />
          </s:Body>
        </s:Envelope>
        """.utf8
    )
}
