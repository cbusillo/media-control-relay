import Foundation
import MediaControlCore
import Testing
@testable import Media_Control_Relay

@Suite("External volume URL contract")
struct ExternalVolumeActionURLTests {
    @Test("Accepts only the three canonical volume URLs")
    func acceptsCanonicalURLs() {
        let cases: [(String, VolumeAction)] = [
            ("media-control-relay://control/volume/up", .up),
            ("media-control-relay://control/volume/down", .down),
            ("media-control-relay://control/volume/mute", .mute),
        ]

        for (rawURL, expectedAction) in cases {
            let url = URL(string: rawURL)
            #expect(
                url.flatMap(ExternalVolumeActionURLParser.action(for:))
                    == expectedAction
            )
        }
    }

    @Test("Rejects noncanonical URL components")
    func rejectsNoncanonicalURLs() {
        let rawURLs = [
            "media-control-relay://other/volume/up",
            "media-control-relay://control/volume/seek",
            "media-control-relay://control/volume/up/extra",
            "media-control-relay://control/volume/up/",
            "media-control-relay://control//volume/up",
            "media-control-relay://control/volume/up?source=test",
            "media-control-relay://control/volume/up#fragment",
            "media-control-relay://user:password@control/volume/up",
            "media-control-relay://control:123/volume/up",
            "MEDIA-CONTROL-RELAY://control/volume/up",
            "media-control-relay://CONTROL/volume/up",
            "media-control-relay://control/volume/%75p",
        ]

        for rawURL in rawURLs {
            let url = URL(string: rawURL)
            #expect(url.flatMap(ExternalVolumeActionURLParser.action(for:)) == nil)
        }
    }

    @Test("Info.plist registers exactly one canonical URL scheme")
    func infoPlistRegistersCanonicalURLScheme() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repoRoot.appendingPathComponent(
            "Config/MediaControlRelay-Info.plist"
        )
        let data = try Data(contentsOf: infoURL)
        let propertyList = try #require(
            try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let urlTypes = try #require(propertyList["CFBundleURLTypes"] as? [[String: Any]])
        #expect(urlTypes.count == 1)
        #expect(urlTypes.first?["CFBundleTypeRole"] as? String == "Viewer")
        #expect(
            urlTypes.first?["CFBundleURLName"] as? String
                == "com.shinycomputers.media-control-relay.external-volume"
        )
        #expect(urlTypes.first?["CFBundleURLSchemes"] as? [String] == [
            "media-control-relay"
        ])
    }
}
