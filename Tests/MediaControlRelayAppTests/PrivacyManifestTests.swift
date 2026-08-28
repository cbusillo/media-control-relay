import Foundation
import Testing

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    @Test("App bundle ships exact privacy declarations")
    func appBundleShipsExactPrivacyDeclarations() throws {
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

        let declarations = Set(manifest.accessedAPITypes.map { declaration in
            PrivacyAPIDeclaration(
                type: declaration.type,
                reasons: Set(declaration.reasons)
            )
        })
        let expectedDeclarations: Set<PrivacyAPIDeclaration> = [
            PrivacyAPIDeclaration(
                type: "NSPrivacyAccessedAPICategoryUserDefaults",
                reasons: ["CA92.1"]
            ),
            PrivacyAPIDeclaration(
                type: "NSPrivacyAccessedAPICategorySystemBootTime",
                reasons: ["35F9.1"]
            ),
        ]

        #expect(manifest.accessedAPITypes.count == expectedDeclarations.count)
        #expect(declarations == expectedDeclarations)
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

private struct PrivacyAPIDeclaration: Hashable {
    let type: String
    let reasons: Set<String>
}
