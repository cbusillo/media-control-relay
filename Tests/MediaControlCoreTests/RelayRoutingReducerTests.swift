import Testing
@testable import MediaControlCore

@Suite("Relay routing reducer")
struct RelayRoutingReducerTests {
    @Test("Active matching routes one command with monotonic sequence")
    func activeCommandEmission() {
        var reducer = activeReducer()

        let first = reducer.reduce(.volumeAction(.up))
        let second = reducer.reduce(.volumeAction(.mute))

        #expect(first.resolvedState == .active)
        #expect(first.command == RelayCommand(sequence: 1, action: .up))
        #expect(second.command == RelayCommand(sequence: 2, action: .mute))
        #expect(!first.cancelHeldGesture)
        #expect(!first.cancelPendingCommand)
    }

    @Test("Dormant routes suppress commands")
    func dormantSuppression() {
        var reducer = activeReducer()
        let transition = reducer.reduce(
            .routeSnapshot(RouteSnapshot(audioOutput: nil, displays: []))
        )

        let output = reducer.reduce(.volumeAction(.down))
        #expect(transition.cancelHeldGesture)
        #expect(transition.cancelPendingCommand)
        #expect(output.resolvedState == .dormant)
        #expect(output.command == nil)
    }

    @Test("Permission loss cancels active work")
    func permissionTransition() {
        var reducer = activeReducer()
        let output = reducer.reduce(.inputMonitoringAuthorization(.denied))

        #expect(output.resolvedState == .needsPermission)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)
    }

    @Test("Suspended observation invalidates the cached activation match")
    func observerSuspension() {
        var reducer = activeReducer()
        let output = reducer.reduce(.routeObservationState(.suspended))

        #expect(!output.activationMatches)
        #expect(output.resolvedState == .dormant)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)

        let resumed = reducer.reduce(.routeObservationState(.observing))
        #expect(!resumed.activationMatches)
        #expect(resumed.resolvedState == .dormant)

        let refreshed = reducer.reduce(.routeSnapshot(matchingRoute()))
        #expect(refreshed.activationMatches)
        #expect(refreshed.resolvedState == .active)
    }

    @Test("Every observing notification requires a subsequent fresh snapshot")
    func observingStartsFreshSnapshotEpoch() {
        var reducer = activeReducer()

        let restarted = reducer.reduce(.routeObservationState(.observing))
        #expect(!restarted.activationMatches)
        #expect(restarted.resolvedState == .dormant)
        #expect(restarted.cancelHeldGesture)
        #expect(restarted.cancelPendingCommand)

        let refreshed = reducer.reduce(.routeSnapshot(matchingRoute()))
        #expect(refreshed.activationMatches)
        #expect(refreshed.resolvedState == .active)
    }

    @Test("Route mismatch cancels held and pending work immediately")
    func routeMismatchCancellation() {
        var reducer = activeReducer()
        let mismatch = RouteSnapshot(
            audioOutput: AudioOutputSnapshot(name: "Other Output", transportKind: .display),
            displays: [DisplaySnapshot(name: "Other Display")]
        )

        let output = reducer.reduce(.routeSnapshot(mismatch))
        #expect(output.resolvedState == .dormant)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)
    }

    @Test("Configuration removal clears matching and recording eligibility")
    func configurationRemoval() {
        var reducer = activeReducer()
        let output = reducer.reduce(.configuration(nil))

        #expect(output.resolvedState == .unconfigured)
        #expect(!output.activationMatches)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)
        #expect(reducer.reduce(.volumeAction(.up)).command == nil)
    }

    @Test("Unknown reachability is checking, not offline")
    func unknownReachability() {
        var reducer = activeReducer()
        let output = reducer.reduce(.transportReachability(.unknown))

        #expect(output.resolvedState == .checkingTarget)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)
    }

    @Test("Local-network denial has a distinct recovery state")
    func localNetworkPermissionTransition() {
        var reducer = activeReducer(targetKind: .upnpMediaRenderer)

        let output = reducer.reduce(.transportReachability(.permissionDenied))

        #expect(output.resolvedState == .needsLocalNetworkPermission)
        #expect(output.cancelHeldGesture)
        #expect(output.cancelPendingCommand)
        #expect(reducer.reduce(.volumeAction(.up)).command == nil)
    }

    @Test("Stopped observation does not reuse a cached match")
    func stoppedObservation() {
        var reducer = activeReducer()
        let output = reducer.reduce(.routeObservationState(.stopped))
        #expect(!output.activationMatches)
        #expect(output.resolvedState == .dormant)
    }

    @Test("Backpressure suppresses commands at the pending limit")
    func backpressure() {
        var reducer = activeReducer(
            policy: VolumeCommandQueuePolicy(maximumPendingCommands: 1)
        )

        let output = reducer.reduce(
            .volumeAction(.up),
            pendingCommandCount: 1
        )

        #expect(output.resolvedState == .active)
        #expect(output.command == nil)
    }

    @Test("Changing configuration resets the command sequence")
    func configurationResetsSequence() {
        var reducer = activeReducer()
        #expect(reducer.reduce(.volumeAction(.up)).command?.sequence == 1)
        #expect(reducer.reduce(.volumeAction(.down)).command?.sequence == 2)

        let configuration = reducer.configuration
        _ = reducer.reduce(.configuration(configuration))

        #expect(reducer.reduce(.volumeAction(.mute)).command?.sequence == 1)
    }

    private func activeReducer(
        policy: VolumeCommandQueuePolicy = .default,
        targetKind: RelayTargetKind = .preview
    ) -> RelayRoutingReducer {
        let route = matchingRoute()
        let configuration = RelayConfiguration(
            target: RelayTargetMetadata(
                kind: targetKind,
                name: "Preview Output",
                stableIdentifier: targetKind == .upnpMediaRenderer
                    ? "uuid:fixture-target"
                    : nil
            ),
            activationRule: ActivationRule(
                audioOutputMatch: "Preview Output",
                displayMatch: "Preview Display",
                requiresDisplay: true
            )
        )
        var reducer = RelayRoutingReducer(policy: policy)
        _ = reducer.reduce(.configuration(configuration))
        _ = reducer.reduce(.routeObservationState(.observing))
        _ = reducer.reduce(.routeSnapshot(route))
        _ = reducer.reduce(.inputMonitoringAuthorization(.granted))
        _ = reducer.reduce(.transportReachability(.reachable))
        return reducer
    }

    private func matchingRoute() -> RouteSnapshot {
        RouteSnapshot(
            audioOutput: AudioOutputSnapshot(name: "Preview Output", transportKind: .display),
            displays: [DisplaySnapshot(name: "Preview Display")]
        )
    }
}
