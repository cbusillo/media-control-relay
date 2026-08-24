import Testing
@testable import VolumeBridgeCore

@Suite("Diagnostics redaction")
struct DiagnosticsRedactionTests {
    @Test("Sensitive fields are removed while public state remains")
    func fieldRedaction() {
        let redacted = DiagnosticsRedaction.redact(fields: [
            "bridge_state": "dormant",
            "server_address": "192.0.2.10",
            "session_key": "000102030405060708090a0b0c0d0e0f",
            "device_uuid": "test-device",
        ])

        #expect(redacted["bridge_state"] == "dormant")
        #expect(redacted["server_address"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["session_key"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["device_uuid"] == DiagnosticsRedaction.redactedValue)
    }

    @Test("Known values are removed from free-form text")
    func textRedaction() {
        let text = "host=TV.Example key=TOP-SECRET device=TEST-DEVICE"
        let redacted = DiagnosticsRedaction.redact(
            text,
            sensitiveValues: ["tv.example", "top-secret", "test-device"]
        )
        #expect(redacted == "host=<redacted> key=<redacted> device=<redacted>")
    }

    @Test("Field matching uses complete words instead of substrings")
    func fieldBoundaries() {
        let redacted = DiagnosticsRedaction.redact(fields: [
            "TVIPAddress": "192.0.2.2",
            "clientId": "client",
            "ghost_count": "2",
            "observer_count": "3",
            "pairingResponse": "response",
            "pairing_key": "secret-key",
            "samsung_session_id": "session",
            "tv_device_uuid": "device",
            "tv_host": "tv.example",
            "tv_ip": "192.0.2.1",
            "tv_serial": "serial",
        ])

        #expect(redacted["TVIPAddress"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["clientId"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["ghost_count"] == "2")
        #expect(redacted["observer_count"] == "3")
        #expect(redacted["pairingResponse"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["pairing_key"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["samsung_session_id"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["tv_device_uuid"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["tv_host"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["tv_ip"] == DiagnosticsRedaction.redactedValue)
        #expect(redacted["tv_serial"] == DiagnosticsRedaction.redactedValue)
    }

    @Test("Allowlisting omits unexpected diagnostics fields")
    func diagnosticsAllowlist() {
        let report = DiagnosticsRedaction.allowlisted(
            fields: [
                "bridge_state": "active",
                "pairing_key": "secret-key",
            ],
            allowedFieldNames: ["bridge_state"]
        )

        #expect(report == ["bridge_state": "active"])
    }
}
