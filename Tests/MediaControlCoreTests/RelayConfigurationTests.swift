import Foundation
import Testing
@testable import MediaControlCore

@Suite("Relay configuration")
struct RelayConfigurationTests {
    @Test("Preview configuration derives display matching from a display route")
    func displayRoute() throws {
        let route = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "Living Room TV HDMI",
                transportKind: .display
            ),
            displays: [DisplaySnapshot(name: "Living Room TV")]
        )

        let configuration = try #require(RelayConfigurationFactory.preview(for: route))
        #expect(configuration.target.kind == .preview)
        #expect(configuration.target.name == "Living Room TV HDMI")
        #expect(configuration.activationRule.audioOutputMatch == "Living Room TV HDMI")
        #expect(configuration.activationRule.displayMatch == "Living Room TV")
        #expect(configuration.activationRule.requiresDisplay)
        #expect(configuration.activationRule.matches(route.activationSnapshot))
    }

    @Test("Display matching selects the display related to the audio output")
    func relatedDisplayOnMultiDisplayRoute() throws {
        let route = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(name: "LG TV", transportKind: .display),
            displays: [
                DisplaySnapshot(name: "Color LCD"),
                DisplaySnapshot(name: "  LG TV  "),
            ]
        )

        let configuration = try #require(RelayConfigurationFactory.preview(for: route))
        #expect(configuration.activationRule.displayMatch == "LG TV")
        #expect(configuration.activationRule.requiresDisplay)
        #expect(configuration.activationRule.matches(route.activationSnapshot))
    }

    @Test("Display transport uses audio-only matching when no display is related")
    func unrelatedDisplays() throws {
        let route = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(name: "Conference HDMI", transportKind: .display),
            displays: [
                DisplaySnapshot(name: "Color LCD"),
                DisplaySnapshot(name: "Projector"),
            ]
        )

        let configuration = try #require(RelayConfigurationFactory.preview(for: route))
        #expect(configuration.activationRule.displayMatch == nil)
        #expect(!configuration.activationRule.requiresDisplay)
        #expect(configuration.activationRule.matches(route.activationSnapshot))
    }

    @Test("Display transport falls back to audio-only matching without a usable display name")
    func displayRouteWithoutName() throws {
        let route = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "AirPlay Receiver",
                transportKind: .display
            ),
            displays: [DisplaySnapshot(name: "   ")]
        )

        let configuration = try #require(RelayConfigurationFactory.preview(for: route))
        #expect(!configuration.activationRule.requiresDisplay)
        #expect(configuration.activationRule.displayMatch == nil)
        #expect(configuration.activationRule.matches(route.activationSnapshot))
    }

    @Test("Preview configuration requires a usable audio output name")
    func missingAudioName() {
        let route = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(name: " ", transportKind: .bluetooth),
            displays: []
        )
        #expect(RelayConfigurationFactory.preview(for: route) == nil)
    }

    @Test("Configuration and activation rule round-trip through Codable")
    func codableRoundTrip() throws {
        let configuration = RelayConfiguration(
            target: RelayTargetMetadata(kind: .preview, name: "Preview Route"),
            activationRule: ActivationRule(
                audioOutputMatch: "Preview Route",
                displayMatch: "Preview Display",
                requiresDisplay: true
            )
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RelayConfiguration.self, from: data)
        #expect(decoded == configuration)
    }
}
