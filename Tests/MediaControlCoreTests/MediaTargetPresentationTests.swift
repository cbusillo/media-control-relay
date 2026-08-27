import Testing
@testable import MediaControlCore

@Suite("Media target presentation")
struct MediaTargetPresentationTests {
    @Test("Normalization uses nonzero bounds and exact rails")
    func normalizationUsesDeclaredBounds() {
        let minimum = MediaTargetVolumeState(
            absoluteVolume: 10,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 50,
            volumeStep: 5
        )
        let midpoint = MediaTargetVolumeState(
            absoluteVolume: 30,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 50,
            volumeStep: 5
        )
        let maximum = MediaTargetVolumeState(
            absoluteVolume: 50,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 50,
            volumeStep: 5
        )

        #expect(MediaTargetVolumeNormalizer.normalize(minimum)?.percentage == 0)
        #expect(MediaTargetVolumeNormalizer.normalize(midpoint)?.percentage == 50)
        #expect(MediaTargetVolumeNormalizer.normalize(maximum)?.percentage == 100)
    }

    @Test("Normalization rejects degenerate capability metadata")
    func normalizationRejectsDegenerateMetadata() {
        let equalBounds = MediaTargetVolumeState(
            absoluteVolume: 10,
            isMuted: false,
            minimumVolume: 10,
            maximumVolume: 10,
            volumeStep: 1
        )

        #expect(MediaTargetVolumeNormalizer.normalize(equalBounds) == nil)
    }

    @Test("Pending presentation uses a fresh baseline and otherwise stays cold")
    func pendingPresentationUsesFreshBaseline() {
        var presentation = MediaTargetPresentationModel(
            timing: MediaTargetPresentationTiming(baselineFreshness: 1)
        )
        let baseline = outcome(volume: 25, generation: 1)

        let receivedBaseline = presentation.receiveProbe(baseline, at: 10)
        #expect(receivedBaseline)
        let beganWithBaseline = presentation.begin(action: .up, generation: 1, at: 10.5)
        #expect(beganWithBaseline)
        #expect(
            presentation.state == .pendingBaseline(
                .up,
                try! #require(MediaTargetVolumeNormalizer.normalize(baseline.confirmedState!))
            )
        )

        presentation.dismiss()
        let beganCold = presentation.begin(action: .up, generation: 1, at: 12.1)
        #expect(beganCold)
        #expect(presentation.state == .pendingCold(.up))
    }

    @Test("Confirmed commands advance only on a current successful outcome")
    func confirmedCommandsRejectStaleAndFailedResults() {
        var presentation = MediaTargetPresentationModel()
        let baseline = outcome(volume: 20, generation: 1)
        let newer = outcome(volume: 30, generation: 2)
        let stale = outcome(volume: 25, generation: 1)
        let failed = MediaTargetSessionOutcome(
            reachability: .unreachable,
            confirmedState: nil,
            generation: 3
        )

        let receivedBaseline = presentation.receiveProbe(baseline, at: 0)
        #expect(receivedBaseline)
        let began = presentation.begin(action: .up, generation: 1, at: 1)
        #expect(began)
        let receivedNewer = presentation.receive(newer, at: 1.1)
        #expect(receivedNewer)
        #expect(presentation.state.confirmedVolume == 30)
        let receivedStale = presentation.receive(stale, at: 1.2)
        #expect(!receivedStale)
        #expect(presentation.state.confirmedVolume == 30)

        let beganAgain = presentation.begin(action: .up, generation: 2, at: 2)
        #expect(beganAgain)
        let receivedFailure = presentation.receive(failed, at: 2.1)
        #expect(receivedFailure)
        #expect(presentation.state.isFailed)
        #expect(presentation.state.confirmedVolume == 30)
    }

    @Test("Mute retains the last confirmed nonzero display level")
    func muteRetainsLastNonzeroLevel() {
        var presentation = MediaTargetPresentationModel()
        let receivedBaseline = presentation.receiveProbe(
            outcome(volume: 40, generation: 1),
            at: 0
        )
        #expect(receivedBaseline)
        let began = presentation.begin(action: .mute, generation: 1, at: 1)
        #expect(began)

        let muted = MediaTargetSessionOutcome(
            reachability: .reachable,
            confirmedState: MediaTargetVolumeState(
                absoluteVolume: 0,
                isMuted: true,
                minimumVolume: 0,
                maximumVolume: 100,
                volumeStep: 5
            ),
            generation: 2
        )
        let receivedMuted = presentation.receive(muted, at: 1.1)
        #expect(receivedMuted)
        #expect(presentation.state.isMuted)
        #expect(presentation.state.displayedVolume == 40)
        #expect(presentation.state.confirmedVolume == 0)
    }

    @Test("Rails remain visible as confirmed state")
    func railsRemainVisible() {
        var presentation = MediaTargetPresentationModel()
        let receivedBaseline = presentation.receiveProbe(
            outcome(volume: 95, generation: 1),
            at: 0
        )
        #expect(receivedBaseline)
        let began = presentation.begin(action: .up, generation: 1, at: 1)
        #expect(began)

        let maximum = outcome(volume: 100, generation: 2)
        let receivedMaximum = presentation.receive(maximum, at: 1.1)
        #expect(receivedMaximum)
        #expect(presentation.state == .rail(.maximum, presentation.state.value!))
    }

    @Test("Invalidation hides level without accepting later stale confirmation")
    func invalidationHidesAndRejectsStaleConfirmation() {
        var presentation = MediaTargetPresentationModel()
        let baseline = outcome(volume: 40, generation: 4)
        let receivedBaseline = presentation.receiveProbe(baseline, at: 0)
        #expect(receivedBaseline)

        presentation.invalidate(.routeMismatch)
        #expect(presentation.state == .routeLost)
        let receivedStale = presentation.receive(
            outcome(volume: 45, generation: 4),
            at: 1
        )
        #expect(!receivedStale)
        #expect(presentation.state == .routeLost)

        presentation.invalidate(.sleep)
        #expect(presentation.state == .suspended)
        presentation.invalidate(.permission)
        #expect(presentation.state == .hidden)
    }

    @Test("Timing policy dismisses settled visible state and throttles announcements")
    func timingPolicy() {
        var presentation = MediaTargetPresentationModel(
            timing: MediaTargetPresentationTiming(
                confirmationDisplayDuration: 2,
                announcementInterval: 1
            )
        )
        let receivedBaseline = presentation.receiveProbe(
            outcome(volume: 40, generation: 1),
            at: 0
        )
        #expect(receivedBaseline)
        let firstAnnouncement = presentation.shouldAnnounce(at: 0)
        #expect(firstAnnouncement)
        let earlyAnnouncement = presentation.shouldAnnounce(at: 0.5)
        #expect(!earlyAnnouncement)
        let secondAnnouncement = presentation.shouldAnnounce(at: 1)
        #expect(secondAnnouncement)
        let beforeDismissal = presentation.advance(to: 1.9)
        #expect(!beforeDismissal)
        let dismissed = presentation.advance(to: 2)
        #expect(dismissed)
        #expect(presentation.state == .hidden)
    }

    private func outcome(volume: Int, generation: UInt64) -> MediaTargetSessionOutcome {
        MediaTargetSessionOutcome(
            reachability: .reachable,
            confirmedState: MediaTargetVolumeState(
                absoluteVolume: volume,
                isMuted: false,
                minimumVolume: 0,
                maximumVolume: 100,
                volumeStep: 5
            ),
            generation: generation
        )
    }
}

private extension MediaTargetPresentationState {
    var value: MediaTargetPresentationValue? {
        switch self {
        case let .confirmed(value), let .muted(value), let .rail(_, value):
            value
        case let .pendingBaseline(_, value):
            value
        case let .failed(value):
            value
        case .hidden, .pendingCold, .suspended, .routeLost:
            nil
        }
    }

    var confirmedVolume: Int? {
        value?.confirmedVolume
    }

    var displayedVolume: Int? {
        value?.displayedVolume
    }

    var isMuted: Bool {
        value?.isMuted == true
    }

    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
