import Foundation
import MediaControlCore
import Testing
@testable import Media_Control_Relay

@Suite("External control URL contract")
struct ExternalControlURLTests {
    @Test("Accepts the canonical volume URLs through the router")
    func acceptsCanonicalVolumeURLs() {
        let cases: [(String, ExternalControlURLRouter.Route)] = [
            ("media-control-relay://control/volume/up", .activeOutputVolume(.up)),
            ("media-control-relay://control/volume/down", .activeOutputVolume(.down)),
            ("media-control-relay://control/volume/mute", .activeOutputVolume(.mute)),
        ]

        for (rawURL, expectedRoute) in cases {
            let url = URL(string: rawURL)
            #expect(url.map(ExternalControlURLRouter.route(for:)) == expectedRoute)
        }
    }

    @Test("Preserves the existing volume parser behavior")
    func preservesExistingVolumeParserBehavior() {
        let cases: [(String, VolumeAction)] = [
            ("media-control-relay://control/volume/up", .up),
            ("media-control-relay://control/volume/down", .down),
            ("media-control-relay://control/volume/mute", .mute),
        ]

        for (rawURL, expectedAction) in cases {
            let url = URL(string: rawURL)
            #expect(url.flatMap(ExternalVolumeActionURLParser.action(for:)) == expectedAction)
        }
    }

    @Test("Accepts the canonical remote URLs through the router")
    func acceptsCanonicalRemoteURLs() {
        let cases: [(String, MediaRemoteAction)] = [
            ("media-control-relay://remote/navigate/up", .navigate(.up)),
            ("media-control-relay://remote/navigate/down", .navigate(.down)),
            ("media-control-relay://remote/navigate/left", .navigate(.left)),
            ("media-control-relay://remote/navigate/right", .navigate(.right)),
            ("media-control-relay://remote/select", .select),
            ("media-control-relay://remote/back", .back),
            ("media-control-relay://remote/home", .home),
            ("media-control-relay://remote/play-pause", .playPause),
            ("media-control-relay://remote/previous", .previous),
            ("media-control-relay://remote/next", .next),
            ("media-control-relay://remote/seek/forward/10", .seek(10)),
            ("media-control-relay://remote/seek/forward/30", .seek(30)),
            ("media-control-relay://remote/seek/backward/10", .seek(-10)),
            ("media-control-relay://remote/seek/backward/30", .seek(-30)),
            ("media-control-relay://remote/volume/up", .volume(1)),
            ("media-control-relay://remote/volume/down", .volume(-1)),
        ]

        for (rawURL, expectedAction) in cases {
            let url = URL(string: rawURL)
            #expect(url.map(ExternalControlURLRouter.route(for:)) == .remote(expectedAction))
        }
    }

    @Test("Rejects noncanonical URLs")
    func rejectsNoncanonicalURLs() {
        let rawURLs = [
            "media-control-relay://control/volume/",
            "media-control-relay://control/volume/up/extra",
            "media-control-relay://control/volume/up?source=test",
            "media-control-relay://control/volume/up#fragment",
            "media-control-relay://control:123/volume/up",
            "media-control-relay://user:password@control/volume/up",
            "MEDIA-CONTROL-RELAY://control/volume/up",
            "media-control-relay://CONTROL/volume/up",
            "media-control-relay://control/volume/%75p",
            "media-control-relay://remote/navigate",
            "media-control-relay://remote/navigate/up/extra",
            "media-control-relay://remote/navigate/up?source=test",
            "media-control-relay://remote/navigate/up#fragment",
            "media-control-relay://remote:123/navigate/up",
            "media-control-relay://user:password@remote/navigate/up",
            "MEDIA-CONTROL-RELAY://remote/navigate/up",
            "media-control-relay://REMOTE/navigate/up",
            "media-control-relay://remote/navigate/%75p",
            "media-control-relay://remote/select/extra",
            "media-control-relay://remote/home?source=test",
            "media-control-relay://remote/seek/forward/20",
            "media-control-relay://remote/seek/backward/20",
            "media-control-relay://remote/volume/mute",
            "media-control-relay://remote/volume/up/extra",
            "media-control-relay://control/volume/up/remote",
            "media-control-relay://remote/navigate/up/../down",
        ]

        for rawURL in rawURLs {
            let url = URL(string: rawURL)
            #expect(url.map(ExternalControlURLRouter.route(for:)) == .rejected)
        }
    }

    @Test("Rejects cross-route cases")
    func rejectsCrossRouteCases() {
        let cases = [
            "media-control-relay://control/navigate/up",
            "media-control-relay://control/select",
            "media-control-relay://control/back",
            "media-control-relay://control/home",
            "media-control-relay://control/play-pause",
            "media-control-relay://control/previous",
            "media-control-relay://control/next",
            "media-control-relay://control/seek/forward/10",
        ]

        for rawURL in cases {
            let url = URL(string: rawURL)
            #expect(url.map(ExternalControlURLRouter.route(for:)) == .rejected)
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
