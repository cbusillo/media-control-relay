import Testing
@testable import MediaControlCore

@Suite("Route observation")
struct RouteObservationTests {
    @Test("Normalization trims names, filters inactive displays, and deduplicates")
    func normalization() {
        let snapshot = RouteSnapshotNormalizer.normalize(
            audioOutput: AudioOutputObservation(
                name: "  Living   Room   HDMI  ",
                stableIdentifier: " audio-1 ",
                transportKind: .display
            ),
            displays: [
                DisplayObservation(
                    name: "  Living   Room  ",
                    stableIdentifier: "display-2"
                ),
                DisplayObservation(
                    name: "Living Room Duplicate",
                    stableIdentifier: "display-2"
                ),
                DisplayObservation(
                    name: "Inactive",
                    stableIdentifier: "display-3",
                    isActive: false
                ),
                DisplayObservation(
                    name: "Disconnected",
                    stableIdentifier: "display-4",
                    isConnected: false
                ),
            ]
        )

        #expect(snapshot.audioOutput?.name == "Living Room HDMI")
        #expect(snapshot.audioOutput?.stableIdentifier == "audio-1")
        #expect(snapshot.audioOutput?.transportKind == .display)
        #expect(snapshot.displays.map(\.name) == ["Living Room"])
        #expect(snapshot.displays.map(\.stableIdentifier) == ["display-2"])
    }

    @Test("Route snapshots bridge to the activation boundary")
    func activationSnapshotBridge() {
        let routeSnapshot = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "Samsung HDMI",
                stableIdentifier: "audio-private",
                transportKind: .display
            ),
            displays: [
                DisplaySnapshot(
                    name: "Samsung Television",
                    stableIdentifier: "display-private"
                )
            ]
        )

        let expected = ActivationSnapshot(
            defaultAudioOutputName: "Samsung HDMI",
            displayNames: ["Samsung Television"]
        )
        #expect(routeSnapshot.activationSnapshot == expected)
        #expect(ActivationSnapshot(routeSnapshot: routeSnapshot) == expected)
    }

    @Test("Displays without names or identifiers remain distinct")
    func unidentifiedDisplaysRemainDistinct() {
        let snapshot = RouteSnapshotNormalizer.normalize(
            audioOutput: nil,
            displays: [
                DisplayObservation(name: nil),
                DisplayObservation(name: nil),
            ]
        )

        #expect(snapshot.displays.count == 2)
    }

    @Test("Unchanged route snapshots are suppressed")
    func unchangedSuppression() {
        let snapshot = sampleSnapshot()
        var coalescer = RouteObservationCoalescer(duplicateWindow: 0.1)

        #expect(coalescer.receive(snapshot, at: 10) == .publish(snapshot))
        #expect(coalescer.receive(snapshot, at: 10.01) == .ignored)
        #expect(coalescer.receive(snapshot, at: 11) == .ignored)
    }

    @Test("Noisy changes keep only the latest bounded pending snapshot")
    func boundedCoalescing() {
        let first = sampleSnapshot()
        let second = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "USB DAC",
                transportKind: .usb
            ),
            displays: first.displays
        )
        let third = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "AirPlay Speaker",
                transportKind: .airPlay
            ),
            displays: first.displays
        )
        var coalescer = RouteObservationCoalescer(duplicateWindow: 0.1)

        #expect(coalescer.receive(first, at: 20) == .publish(first))
        #expect(coalescer.receive(second, at: 20.02) == .scheduled(deadline: 20.1))
        #expect(coalescer.receive(third, at: 20.03) == .scheduled(deadline: 20.1))
        #expect(coalescer.flush(at: 20.09) == .scheduled(deadline: 20.1))
        #expect(coalescer.flush(at: 20.1) == .publish(third))
    }

    @Test("Lifecycle start, stop, sleep, and wake are idempotent")
    func lifecycle() {
        var lifecycle = RouteObservationLifecycle()

        #expect(lifecycle.state == .stopped)
        #expect(lifecycle.start() == .registerRouteObserversAndPublishFreshSnapshot)
        #expect(lifecycle.state == .observing)
        #expect(lifecycle.start() == .none)
        #expect(lifecycle.wake() == .none)
        #expect(lifecycle.sleep() == .unregisterRouteObservers)
        #expect(lifecycle.state == .suspended)
        #expect(lifecycle.sleep() == .none)
        #expect(lifecycle.wake() == .registerRouteObserversAndPublishFreshSnapshot)
        #expect(lifecycle.state == .observing)
        #expect(lifecycle.wake() == .none)
        #expect(lifecycle.stop() == .unregisterRouteObservers)
        #expect(lifecycle.state == .stopped)
        #expect(lifecycle.stop() == .none)
    }

    @Test("Wake permits one fresh snapshot after observers resume")
    func freshWakeSnapshot() {
        let snapshot = sampleSnapshot()
        var lifecycle = RouteObservationLifecycle()
        var coalescer = RouteObservationCoalescer()

        #expect(lifecycle.start() == .registerRouteObserversAndPublishFreshSnapshot)
        #expect(coalescer.receive(snapshot, at: 30) == .publish(snapshot))
        #expect(lifecycle.sleep() == .unregisterRouteObservers)
        coalescer.reset()
        #expect(lifecycle.wake() == .registerRouteObserversAndPublishFreshSnapshot)
        #expect(coalescer.receive(snapshot, at: 31) == .publish(snapshot))
        #expect(coalescer.receive(snapshot, at: 31.01) == .ignored)
    }

    @Test("Diagnostics expose only coarse route state")
    func privacySafeDiagnostics() {
        let snapshot = RouteSnapshotNormalizer.normalize(
            audioOutput: AudioOutputObservation(
                name: "Private HDMI Name",
                stableIdentifier: "private-audio-uid",
                transportKind: .display
            ),
            displays: [
                DisplayObservation(
                    name: "Private Display Name",
                    stableIdentifier: "private-display-id"
                )
            ]
        )
        let diagnostics = RouteObservationDiagnostics(
            state: .observing,
            snapshot: snapshot
        )

        #expect(diagnostics.fields == [
            "route_observation": "observing",
            "audio_transport": "display",
            "active_displays": "1",
        ])
        #expect(!diagnostics.fields.values.contains("Private HDMI Name"))
        #expect(!diagnostics.fields.values.contains("Private Display Name"))
        #expect(!diagnostics.fields.values.contains("private-audio-uid"))
        #expect(!diagnostics.fields.values.contains("private-display-id"))
    }

    private func sampleSnapshot() -> RouteSnapshot {
        RouteSnapshot(
            audioOutput: AudioOutputSnapshot(
                name: "Built-in Output",
                transportKind: .builtIn
            ),
            displays: [
                DisplaySnapshot(name: "Built-in Display")
            ]
        )
    }
}
