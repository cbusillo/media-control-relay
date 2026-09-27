import Foundation
import Testing

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    @Test("App bundle ships a no-tracking privacy manifest")
    func appBundleShipsNoTrackingPrivacyManifest() throws {
        let manifestURL = try #require(
            Bundle.main.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        let manifest = try PropertyListDecoder().decode(
            PrivacyManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        #expect(!manifest.tracking)
        #expect(manifest.trackingDomains.isEmpty)
        #expect(manifest.collectedDataTypes.isEmpty)

        #expect(manifest.accessedAPITypes.allSatisfy { !$0.reasons.isEmpty })
    }
}

private struct PrivacyManifest: Decodable {
    let tracking: Bool
    let trackingDomains: [String]
    let collectedDataTypes: [CollectedDataType]
    let accessedAPITypes: [AccessedAPIType]

    enum CodingKeys: String, CodingKey {
        case tracking = "NSPrivacyTracking"
        case trackingDomains = "NSPrivacyTrackingDomains"
        case collectedDataTypes = "NSPrivacyCollectedDataTypes"
        case accessedAPITypes = "NSPrivacyAccessedAPITypes"
    }
}

private struct CollectedDataType: Decodable {}

private struct AccessedAPIType: Decodable {
    let type: String
    let reasons: [String]

    enum CodingKeys: String, CodingKey {
        case type = "NSPrivacyAccessedAPIType"
        case reasons = "NSPrivacyAccessedAPITypeReasons"
    }
}
