import Testing
@testable import MediaControlCore

@Suite("Activation matching")
struct ActivationRuleTests {
    @Test("Audio and display matches are case and diacritic insensitive")
    func matchesAudioAndDisplay() {
        let rule = ActivationRule(audioOutputMatch: "samsung", displayMatch: "sámsung")
        let snapshot = ActivationSnapshot(
            defaultAudioOutputName: "SAMSUNG HDMI",
            displayNames: ["Samsung Television"]
        )
        #expect(rule.matches(snapshot))
    }

    @Test("A display is required by default")
    func displayRequired() {
        let rule = ActivationRule(audioOutputMatch: "Samsung")
        let snapshot = ActivationSnapshot(
            defaultAudioOutputName: "Samsung",
            displayNames: []
        )
        #expect(!rule.matches(snapshot))
    }

    @Test("Display matching can be disabled")
    func displayOptional() {
        let rule = ActivationRule(
            audioOutputMatch: "Samsung",
            requiresDisplay: false
        )
        let snapshot = ActivationSnapshot(
            defaultAudioOutputName: "Samsung HDMI",
            displayNames: []
        )
        #expect(rule.matches(snapshot))
    }

    @Test("An empty audio match never activates")
    func emptyAudioMatch() {
        let rule = ActivationRule(audioOutputMatch: "   ", requiresDisplay: false)
        let snapshot = ActivationSnapshot(
            defaultAudioOutputName: "Samsung",
            displayNames: ["Samsung"]
        )
        #expect(!rule.matches(snapshot))
    }
}
