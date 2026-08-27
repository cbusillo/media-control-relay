import Testing
@testable import MediaControlCore

@Suite("Media target presentation")
struct MediaTargetPresentationTests {
    @Test("Normalization preserves declared nonzero bounds and step")
    func normalizationUsesDeclaredBoundsAndStep() {
        let minimum = state(volume: 10, minimum: 10, maximum: 50, step: 5)
        let midpoint = state(volume: 30, minimum: 10, maximum: 50, step: 5)
        let maximum = state(volume: 50, minimum: 10, maximum: 50, step: 5)

        expect(MediaTargetVolumeNormalizer.normalize(minimum)?.percentage == 0)
        expect(MediaTargetVolumeNormalizer.normalize(midpoint)?.percentage == 50)
        expect(MediaTargetVolumeNormalizer.normalize(maximum)?.percentage == 100)
        expect(MediaTargetVolumeNormalizer.normalize(midpoint)?.volumeStep == 5)
    }

    @Test("Normalization rejects degenerate capability metadata")
    func normalizationRejectsDegenerateMetadata() {
        expect(MediaTargetVolumeNormalizer.normalize(
            state(volume: 10, minimum: 10, maximum: 10, step: 1)
        ) == nil)
    }

    @Test("Presentation values are constructible by public clients")
    func presentationValueHasPublicInitializer() {
        let value = MediaTargetPresentationValue(
            normalizedLevel: 0.5,
            confirmedVolume: 30,
            displayedVolume: 30,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 50,
            volumeStep: 5
        )

        expect(value.percentage == 50)
    }

    @Test("Pending presentation uses a fresh baseline and otherwise stays cold")
    func pendingPresentationUsesFreshBaseline() {
        var presentation = MediaTargetPresentationModel(
            timing: MediaTargetPresentationTiming(baselineFreshness: 1)
        )
        let baseline = outcome(volume: 25, generation: 1)
        let epoch = presentation.invalidationEpoch

        expect(presentation.receiveProbe(baseline, epoch: epoch, at: 10))
        expect(presentation.state == .hidden)
        expect(!presentation.shouldAnnounce(at: 10))
        expect(presentation.begin(action: .up, requestID: 1, epoch: epoch, at: 10.5))
        guard let confirmedState = baseline.confirmedState,
              let expectedValue = MediaTargetVolumeNormalizer.normalize(confirmedState) else {
            Issue.record("Expected valid presentation baseline")
            return
        }
        expect(presentation.state == .pendingBaseline(.up, expectedValue))

        presentation.dismiss()
        expect(presentation.begin(action: .up, requestID: 2, epoch: epoch, at: 12.1))
        expect(presentation.state == .pendingCold(.up))
    }

    @Test("Rejected probes do not update mute-retention state")
    func rejectedProbeDoesNotMutateMuteRetention() {
        var presentation = MediaTargetPresentationModel()
        let epoch = presentation.invalidationEpoch

        expect(presentation.receiveProbe(
            outcome(volume: 30, generation: 1, minimum: 10, maximum: 50, step: 5),
            epoch: epoch,
            at: 0
        ))
        expect(presentation.begin(action: .mute, requestID: 1, epoch: epoch, at: 1))
        expect(!presentation.receiveProbe(
            outcome(volume: 45, generation: 2, minimum: 10, maximum: 50, step: 5),
            epoch: epoch,
            at: 1.1
        ))
        expect(presentation.receive(
            outcome(
                volume: 10,
                isMuted: true,
                generation: 3,
                minimum: 10,
                maximum: 50,
                step: 5
            ),
            requestID: 1,
            epoch: epoch,
            at: 1.2
        ))

        expect(presentation.state.value?.displayedVolume == 30)
        expect(presentation.state.value?.confirmedVolume == 10)
    }

    @Test("Each begin accepts only its actual request result")
    func commandResultsCannotAliasAPreviousRequest() {
        var presentation = MediaTargetPresentationModel()
        let epoch = presentation.invalidationEpoch

        expect(presentation.receiveProbe(outcome(volume: 20, generation: 1), epoch: epoch, at: 0))
        expect(presentation.begin(action: .up, requestID: 1, epoch: epoch, at: 1))
        expect(presentation.begin(action: .up, requestID: 2, epoch: epoch, at: 1.01))
        expect(!presentation.receive(
            outcome(volume: 25, generation: 2),
            requestID: 1,
            epoch: epoch,
            at: 1.1
        ))
        expect(presentation.receive(
            outcome(volume: 30, generation: 3),
            requestID: 2,
            epoch: epoch,
            at: 1.2
        ))
        expect(presentation.state.value?.confirmedVolume == 30)
    }

    @Test("Mute retains the last confirmed level above a nonzero minimum")
    func muteRetainsLastNonzeroLevelRelativeToMinimum() {
        var presentation = MediaTargetPresentationModel()
        let epoch = presentation.invalidationEpoch
        expect(presentation.receiveProbe(
            outcome(volume: 30, generation: 1, minimum: 10, maximum: 50, step: 5),
            epoch: epoch,
            at: 0
        ))
        expect(presentation.begin(action: .mute, requestID: 1, epoch: epoch, at: 1))
        expect(presentation.receive(
            outcome(
                volume: 10,
                isMuted: true,
                generation: 2,
                minimum: 10,
                maximum: 50,
                step: 5
            ),
            requestID: 1,
            epoch: epoch,
            at: 1.1
        ))

        expect(presentation.state.value?.displayedVolume == 30)
        expect(presentation.state.value?.confirmedVolume == 10)
        expect(presentation.state.value?.isMuted == true)
    }

    @Test("Invalidation clears caches and accepts a fresh session generation")
    func invalidationClearsPresentationCachesAndRecovers() {
        var presentation = MediaTargetPresentationModel()
        let originalEpoch = presentation.invalidationEpoch
        expect(presentation.receiveProbe(
            outcome(volume: 40, generation: 12),
            epoch: originalEpoch,
            at: 0
        ))
        expect(!presentation.shouldAnnounce(at: 0))

        presentation.invalidate(.configuration)
        let freshEpoch = presentation.invalidationEpoch
        expect(freshEpoch != originalEpoch)
        expect(presentation.state == .hidden)
        expect(presentation.begin(action: .up, requestID: 1, epoch: freshEpoch, at: 0.1))
        expect(presentation.state == .pendingCold(.up))
        expect(presentation.fail(requestID: 1, epoch: freshEpoch, at: 0.2))
        expect(presentation.state == .failed(nil))
        expect(!presentation.receiveProbe(
            outcome(volume: 45, generation: 13),
            epoch: originalEpoch,
            at: 0.3
        ))
        expect(presentation.receiveProbe(
            outcome(volume: 15, generation: 1),
            epoch: freshEpoch,
            at: 0.4
        ))
        expect(presentation.state == .hidden)
        expect(presentation.begin(action: .up, requestID: 2, epoch: freshEpoch, at: 0.5))
        expect(presentation.receive(
            outcome(volume: 15, generation: 2),
            requestID: 2,
            epoch: freshEpoch,
            at: 0.6
        ))
        expect(presentation.state.value?.confirmedVolume == 15)
        expect(presentation.shouldAnnounce(at: 0.6))
    }

    @Test("Rails remain visible as confirmed state")
    func railsRemainVisible() {
        var presentation = MediaTargetPresentationModel()
        let epoch = presentation.invalidationEpoch
        expect(presentation.receiveProbe(outcome(volume: 95, generation: 1), epoch: epoch, at: 0))
        expect(presentation.begin(action: .up, requestID: 1, epoch: epoch, at: 1))
        expect(presentation.receive(
            outcome(volume: 100, generation: 2),
            requestID: 1,
            epoch: epoch,
            at: 1.1
        ))
        expect(presentation.state == .rail(.maximum, presentation.state.value!))
    }

    @Test("Timing preserves pending state and dismisses confirmed state")
    func timingPolicy() {
        var presentation = MediaTargetPresentationModel(
            timing: MediaTargetPresentationTiming(
                confirmationDisplayDuration: 2,
                announcementInterval: 1
            )
        )
        let epoch = presentation.invalidationEpoch
        expect(presentation.receiveProbe(outcome(volume: 40, generation: 1), epoch: epoch, at: 0))
        expect(presentation.begin(action: .up, requestID: 1, epoch: epoch, at: 0.1))
        expect(!presentation.advance(to: 3))
        expect(presentation.state.isVisible)
        expect(presentation.receive(
            outcome(volume: 45, generation: 2),
            requestID: 1,
            epoch: epoch,
            at: 3.1
        ))
        expect(presentation.shouldAnnounce(at: 3.1))
        expect(!presentation.shouldAnnounce(at: 4.1))
        expect(!presentation.advance(to: 5))
        expect(presentation.advance(to: 5.2))
        expect(presentation.state == .hidden)
        expect(presentation.receiveProbe(outcome(volume: 45, generation: 3), epoch: epoch, at: 5.3))
        expect(presentation.begin(action: .up, requestID: 2, epoch: epoch, at: 5.4))
        expect(presentation.receive(
            outcome(volume: 45, generation: 4),
            requestID: 2,
            epoch: epoch,
            at: 5.5
        ))
        expect(presentation.shouldAnnounce(at: 5.5))
    }

    private func expect(_ condition: Bool) {
        #expect(condition)
    }

    private func outcome(
        volume: Int,
        isMuted: Bool = false,
        generation: UInt64,
        minimum: Int = 0,
        maximum: Int = 100,
        step: Int = 5
    ) -> MediaTargetSessionOutcome {
        MediaTargetSessionOutcome(
            reachability: .reachable,
            confirmedState: state(
                volume: volume,
                isMuted: isMuted,
                minimum: minimum,
                maximum: maximum,
                step: step
            ),
            generation: generation
        )
    }

    private func state(
        volume: Int,
        isMuted: Bool = false,
        minimum: Int,
        maximum: Int,
        step: Int
    ) -> MediaTargetVolumeState {
        MediaTargetVolumeState(
            absoluteVolume: volume,
            isMuted: isMuted,
            minimumVolume: minimum,
            maximumVolume: maximum,
            volumeStep: step
        )
    }
}
