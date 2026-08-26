import Testing
@testable import MediaControlCore

@Suite("Relay status copy")
struct RelayStatusCopyTests {
    @Test("Preview active copy is honest about the sink and Mac behavior")
    func previewActiveHonesty() {
        let copy = RelayStatusCopyCatalog.copy(for: .active, targetKind: .preview)

        #expect(copy.title.localizedCaseInsensitiveContains("record"))
        #expect(copy.detail.localizedCaseInsensitiveContains("preview target"))
        #expect(copy.detail.localizedCaseInsensitiveContains("no TV or media device"))
        #expect(copy.detail.localizedCaseInsensitiveContains("connected or controlled"))
        #expect(copy.detail.localizedCaseInsensitiveContains("Mac continues handling volume normally"))
        #expect(!copy.detail.localizedCaseInsensitiveContains("controlling"))
    }

    @Test("Checking target has distinct copy and icon")
    func checkingTargetCopy() {
        let copy = RelayStatusCopyCatalog.copy(for: .checkingTarget, targetKind: .preview)
        #expect(copy.title == "Checking preview target")
        #expect(copy.systemImage == "questionmark.circle")
    }

    @Test("Unavailable preview copy preserves normal Mac handling")
    func previewOfflineHonesty() {
        let copy = RelayStatusCopyCatalog.copy(for: .offline, targetKind: .preview)

        #expect(copy.detail.localizedCaseInsensitiveContains("Mac continues handling volume normally"))
        #expect(!copy.detail.localizedCaseInsensitiveContains("remains unchanged"))
    }

    @Test("Unconfigured copy points to the available preview setup")
    func unconfiguredSetupCopy() {
        let copy = RelayStatusCopyCatalog.copy(for: .unconfigured, targetKind: nil)

        #expect(copy.title == "No media target selected")
        #expect(copy.detail.localizedCaseInsensitiveContains("create"))
        #expect(copy.detail.localizedCaseInsensitiveContains("Settings"))
        #expect(!copy.detail.localizedCaseInsensitiveContains("coming soon"))
    }

    @Test("Local-network recovery copy is distinct from volume-key permission")
    func localNetworkPermissionCopy() {
        let copy = RelayStatusCopyCatalog.copy(
            for: .needsLocalNetworkPermission,
            targetKind: .upnpMediaRenderer
        )

        #expect(copy.title.localizedCaseInsensitiveContains("local network"))
        #expect(!copy.title.localizedCaseInsensitiveContains("volume key"))
        #expect(copy.systemImage == "network.badge.shield.half.filled")
    }

    @Test("Target authentication rejection does not claim macOS permission denial")
    func targetAuthenticationCopy() {
        let copy = RelayStatusCopyCatalog.copy(
            for: .targetAuthenticationRejected,
            targetKind: .upnpMediaRenderer
        )

        #expect(copy.title.localizedCaseInsensitiveContains("rejected"))
        #expect(!copy.detail.localizedCaseInsensitiveContains("privacy & security"))
        #expect(!copy.detail.localizedCaseInsensitiveContains("local network"))
    }
}
