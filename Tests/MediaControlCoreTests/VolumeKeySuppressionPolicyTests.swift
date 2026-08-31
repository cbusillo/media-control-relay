import Foundation
import Testing
@testable import MediaControlCore

@Suite("Volume key suppression policy")
struct VolumeKeySuppressionPolicyTests {
    @Test("Readiness arms only for a fresh dispatch-ready active target")
    func readinessRequiresEverySafetyInput() {
        let ready = readiness()
        #expect(VolumeKeySuppressionPolicy.isArmed(ready))

        let variants = [
            readiness(relayState: .dormant),
            readiness(routeObservationIsFresh: false),
            readiness(inputMonitoringGranted: false),
            readiness(accessibilityGranted: false),
            readiness(dispatchReady: false),
            readiness(sessionReady: false),
            readiness(awaitingWakeCompletion: true),
            readiness(confirmedTargetAge: nil),
            readiness(confirmedTargetAge: -0.001),
            readiness(confirmedTargetAge: 1.001),
        ]

        for variant in variants {
            #expect(!VolumeKeySuppressionPolicy.isArmed(variant))
        }
    }

    @Test("Listen-only mode always passes an unlatched press")
    func listenOnlyPassesPress() {
        let evaluation = evaluate(
            event: event(.up, .pressed),
            mode: .listenOnly,
            authority: authority()
        )

        #expect(evaluation.decision == .passThrough)
        #expect(evaluation.state.latchedActions.isEmpty)
    }

    @Test("Conditional mode consumes only with a fresh armed authority")
    func conditionalRequiresFreshAuthority() {
        let authorities: [VolumeKeySuppressionAuthority?] = [
            nil,
            authority(isArmed: false),
            authority(issuedAt: 11),
            authority(issuedAt: 9, validFor: 0.999),
        ]

        for candidate in authorities {
            let evaluation = evaluate(
                event: event(.down, .pressed),
                authority: candidate
            )
            #expect(evaluation.decision == .passThrough)
            #expect(evaluation.state.latchedActions.isEmpty)
        }

        let boundary = evaluate(
            event: event(.down, .pressed),
            authority: authority(issuedAt: 9, validFor: 1)
        )
        #expect(boundary.decision == .consume)
        #expect(Set(boundary.state.latchedActions.keys) == [.down])
    }

    @Test("Consumed press latches repeats and release across revocation")
    func latchPreservesGestureSymmetry() {
        let pressed = evaluate(
            event: event(.up, .pressed),
            authority: authority()
        )
        let repeated = evaluate(
            event: event(.up, .pressed, isRepeat: true),
            mode: .listenOnly,
            authority: nil,
            state: pressed.state
        )
        let released = evaluate(
            event: event(.up, .released),
            mode: .listenOnly,
            authority: nil,
            state: repeated.state
        )

        #expect(pressed.decision == .consume)
        #expect(repeated.decision == .consume)
        #expect(released.decision == .consume)
        #expect(released.state.latchedActions.isEmpty)
    }

    @Test("Passed press keeps its release fail-open after authority appears")
    func passedPressDoesNotLatchRelease() {
        let pressed = evaluate(
            event: event(.mute, .pressed),
            mode: .listenOnly,
            authority: nil
        )
        let released = evaluate(
            event: event(.mute, .released),
            authority: authority(),
            state: pressed.state
        )

        #expect(pressed.decision == .passThrough)
        #expect(released.decision == .passThrough)
        #expect(released.state.latchedActions.isEmpty)
    }

    @Test("Multiple latched actions release independently")
    func multipleActionsReleaseIndependently() {
        let first = evaluate(
            event: event(.up, .pressed),
            authority: authority()
        )
        let second = evaluate(
            event: event(.down, .pressed),
            authority: authority(),
            state: first.state
        )
        let releaseUp = evaluate(
            event: event(.up, .released),
            authority: nil,
            state: second.state
        )

        #expect(Set(second.state.latchedActions.keys) == [.up, .down])
        #expect(releaseUp.decision == .consume)
        #expect(Set(releaseUp.state.latchedActions.keys) == [.down])
    }

    @Test("A lost release cannot leave a key permanently latched")
    func staleLatchExpiresFailOpen() {
        let pressed = evaluate(
            event: event(.up, .pressed),
            authority: authority()
        )
        let nextPress = evaluate(
            event: event(.up, .pressed),
            mode: .listenOnly,
            authority: nil,
            state: pressed.state,
            uptime: 12,
            maximumLatchIdle: 1
        )

        #expect(nextPress.decision == .passThrough)
        #expect(nextPress.state.latchedActions.isEmpty)
    }

    @Test("Suppression timing stays bounded and keeps keepalive within freshness")
    func suppressionTimingBoundsValues() {
        let timing = VolumeKeySuppressionTiming(
            targetFreshness: 3,
            keepaliveInterval: 5,
            maximumLatchIdle: -1
        )

        #expect(timing.targetFreshness == 3)
        #expect(timing.keepaliveInterval == 3)
        #expect(timing.maximumLatchIdle == 0)
    }

    private func readiness(
        relayState: RelayState = .active,
        routeObservationIsFresh: Bool = true,
        inputMonitoringGranted: Bool = true,
        accessibilityGranted: Bool = true,
        dispatchReady: Bool = true,
        sessionReady: Bool = true,
        awaitingWakeCompletion: Bool = false,
        confirmedTargetAge: TimeInterval? = 0.25
    ) -> VolumeKeySuppressionReadinessInputs {
        VolumeKeySuppressionReadinessInputs(
            relayState: relayState,
            routeObservationIsFresh: routeObservationIsFresh,
            inputMonitoringGranted: inputMonitoringGranted,
            accessibilityGranted: accessibilityGranted,
            dispatchReady: dispatchReady,
            sessionReady: sessionReady,
            awaitingWakeCompletion: awaitingWakeCompletion,
            confirmedTargetAge: confirmedTargetAge,
            maximumTargetAge: 1
        )
    }

    private func authority(
        issuedAt: TimeInterval = 9.5,
        validFor: TimeInterval = 1,
        isArmed: Bool = true
    ) -> VolumeKeySuppressionAuthority {
        VolumeKeySuppressionAuthority(
            issuedAt: issuedAt,
            validFor: validFor,
            isArmed: isArmed
        )
    }

    private func event(
        _ action: VolumeAction,
        _ phase: VolumeKeyPhase,
        isRepeat: Bool = false
    ) -> VolumeKeyEvent {
        VolumeKeyEvent(
            action: action,
            phase: phase,
            isRepeat: isRepeat,
            timestamp: 10
        )
    }

    private func evaluate(
        event: VolumeKeyEvent,
        mode: VolumeKeySuppressionMode = .conditional,
        authority: VolumeKeySuppressionAuthority?,
        state: VolumeKeySuppressionState = VolumeKeySuppressionState(),
        uptime: TimeInterval = 10,
        maximumLatchIdle: TimeInterval = VolumeKeySuppressionTiming.default.maximumLatchIdle
    ) -> VolumeKeySuppressionEvaluation {
        VolumeKeySuppressionPolicy.evaluate(
            event: event,
            mode: mode,
            authority: authority,
            state: state,
            uptime: uptime,
            maximumLatchIdle: maximumLatchIdle
        )
    }
}
