import AppKit
import Foundation
import MediaControlCore
import Testing
import UPnPMediaTarget
@testable import Media_Control_Relay

@Suite("Relay app target health", .serialized)
@MainActor
struct RelayAppModelTests {
    @Test("Matching UPnP configuration becomes active after a successful probe")
    func successfulProbeBecomesActive() async {
        let target = AppModelTargetStub()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }

        #expect(harness.model.relayState == .active)
        #expect(harness.model.targetPresentationState == .hidden)
        #expect(announcements.values.isEmpty)
        harness.cleanup()
    }

    @Test("Network transitions invalidate target work and recover on a usable path")
    func networkTransitionsInvalidateAndRecover() async {
        let target = AppModelTargetStub()
        let recorder = AppModelInvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                await recorder.record(reason)
            }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil { harness.model.relayState == .active }
        harness.networkPathObserver.publish(
            NetworkPathSnapshot(status: .unavailable)
        )
        await waitUntil { harness.model.relayState == .offline }
        await waitUntilAsync {
            await recorder.reasons.contains(.networkContextChanged)
        }

        harness.networkPathObserver.publish(availableNetworkSnapshot())
        await waitUntil { harness.model.relayState == .active }

        #expect(harness.model.networkTransitionCount == 2)
        #expect(await target.readCount == 2)
        harness.cleanup()
    }

    @Test("Local-network denial is OS evidence and does not probe until recovery")
    func localNetworkDenialRecovery() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil { harness.model.relayState == .active }
        harness.networkPathObserver.publish(
            NetworkPathSnapshot(status: .localNetworkDenied)
        )
        await waitUntil {
            harness.model.relayState == .needsLocalNetworkPermission
        }
        harness.model.retryTargetConnection()
        await Task.yield()

        #expect(await target.readCount == 1)
        #expect(harness.model.targetRecoveryAttempts == 1)
        #expect(harness.model.diagnosticsSummary.contains(
            "network_path=local-network-denied"
        ))

        harness.networkPathObserver.setCurrentSnapshotWithoutPublishing(
            availableNetworkSnapshot()
        )
        harness.model.retryTargetConnection()
        await waitUntil { harness.model.relayState == .active }

        #expect(await target.readCount == 2)
        #expect(harness.model.targetRecoveryAttempts == 2)
        harness.cleanup()
    }

    @Test("Target-reported local-network denial retries on activation while path stays available")
    func targetReportedLocalNetworkDenialRecovery() async {
        let target = LocalNetworkRetryingAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil {
            harness.model.relayState == .needsLocalNetworkPermission
        }
        #expect(harness.model.diagnosticsSummary.contains("network_path=available"))

        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }

        #expect(await target.readCount == 2)
        #expect(harness.model.targetRecoveryAttempts == 0)
        harness.cleanup()
    }

    @Test("App activation refreshes network denial before retrying a probe")
    func activationRefreshesNetworkFirst() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil { harness.model.relayState == .active }
        harness.networkPathObserver.setCurrentSnapshotWithoutPublishing(
            NetworkPathSnapshot(status: .localNetworkDenied)
        )
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil {
            harness.model.relayState == .needsLocalNetworkPermission
        }

        #expect(await target.readCount == 1)
        harness.cleanup()
    }

    @Test("Target authentication rejection never claims local-network denial")
    func targetAuthenticationRejection() async {
        let target = AuthenticationRejectedAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil {
            harness.model.relayState == .targetAuthenticationRejected
        }

        #expect(!harness.model.statusCopy.detail.localizedCaseInsensitiveContains(
            "local network"
        ))
        #expect(harness.model.diagnosticsSummary.contains(
            "relay_state=target-authentication-rejected"
        ))
        harness.cleanup()
    }

    @Test("Preview routing remains active across network transitions")
    func previewIgnoresNetworkTransitions() async {
        let harness = makeHarness(
            configuration: makePreviewConfiguration(),
            session: nil,
            initialNetworkSnapshot: availableNetworkSnapshot()
        )

        await waitUntil { harness.model.relayState == .active }
        harness.networkPathObserver.publish(
            NetworkPathSnapshot(status: .localNetworkDenied)
        )
        await Task.yield()

        #expect(harness.model.relayState == .active)
        #expect(harness.model.networkTransitionCount == 1)
        harness.cleanup()
    }

    @Test("Repeated permission refresh does not restart an in-flight probe")
    func permissionRefreshDoesNotRestartProbe() async {
        let target = BlockingAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntilAsync { await target.readCount == 1 }
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        harness.model.refreshInputMonitoring()
        await Task.yield()

        #expect(await target.readCount == 1)
        await target.releaseRead()
        await waitUntil { harness.model.relayState == .active }

        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Route mismatch suppresses a stale probe result")
    func routeMismatchSuppressesStaleProbe() async {
        let target = BlockingAppModelTarget()
        let recorder = AppModelInvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                await recorder.record(reason)
            }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntilAsync { await target.readCount == 1 }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        await target.releaseRead()
        await waitUntilAsync {
            await recorder.reasons.contains(.routeContextChanged)
        }

        #expect(harness.model.relayState == .dormant)
        harness.cleanup()
    }

    @Test("Missing stable identity resolves to offline instead of checking forever")
    func missingStableIdentityIsOffline() {
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: nil),
            session: nil
        )

        #expect(harness.model.relayState == .offline)
        harness.cleanup()
    }

    @Test("Offline target retries when permission state is refreshed")
    func offlineTargetRetriesOnRefresh() async {
        let target = RetryingAppModelTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .offline }
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }

        #expect(await target.readCount == 2)
        harness.cleanup()
    }

    @Test("Activation-equivalent route snapshots do not restart probing")
    func equivalentRouteDoesNotRestartProbe() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let initialReadCount = await target.readCount
        harness.routeObserver.publish(
            RouteSnapshot(
                audioOutput: AudioOutputSnapshot(
                    name: "Fixture Output",
                    transportKind: .display
                ),
                displays: [DisplaySnapshot(name: "Unrelated Display")]
            )
        )
        await Task.yield()

        #expect(await target.readCount == initialReadCount)
        #expect(harness.model.relayState == .active)
        harness.cleanup()
    }

    @Test("Wake performs one lifecycle-invalidated probe")
    func wakePerformsOneProbe() async {
        let target = AppModelTargetStub()
        let recorder = AppModelInvalidationRecorder()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { reason in
                await recorder.record(reason)
            }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let initialReadCount = await target.readCount
        harness.routeObserver.sleep()
        await waitUntilAsync {
            await recorder.reasons.last == .lifecycleChanged
        }
        let wakeReasonStart = await recorder.reasons.count
        harness.routeObserver.wake(makeRoute())
        await waitUntilAsync { await target.readCount == initialReadCount + 1 }
        await waitUntil { harness.model.relayState == .active }

        let wakeReasons = await Array(recorder.reasons.dropFirst(wakeReasonStart))
        #expect(wakeReasons == [.lifecycleChanged])
        #expect(await target.readCount == initialReadCount + 1)
        harness.cleanup()
    }

    @Test("Eligible actions execute through the physical target")
    func eligibleActionExecutes() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.appliedOperations == [.setVolume(6)] }

        #expect(harness.model.targetCommandsDispatched == 1)
        #expect(harness.model.targetCommandsFailed == 0)
        #expect(harness.model.relayState == .active)
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 6)
        harness.cleanup()
    }

    @Test("A target switch never presents the prior target during an immediate keypress")
    func targetSwitchImmediateKeypressStartsCold() async {
        let firstTarget = AppModelTargetStub()
        let secondTarget = AppModelTargetStub(
            initialState: MediaTargetVolumeState(
                absoluteVolume: 40,
                isMuted: false,
                minimumVolume: 10,
                maximumVolume: 50,
                volumeStep: 5
            )
        )
        let firstSession = MediaTargetSession(target: firstTarget, invalidateResolution: { _ in })
        let secondSession = MediaTargetSession(target: secondTarget, invalidateResolution: { _ in })
        var sessions = [firstSession, secondSession]
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "first-target"),
            session: nil,
            sessionFactory: { _ in
                sessions.isEmpty ? nil : sessions.removeFirst()
            }
        )

        await waitUntil { harness.model.relayState == .active }
        #expect(harness.model.targetPresentationState == .hidden)
        harness.model.selectDiscoveredTarget(
            MediaTargetDiscoveryChoice(id: "second-target", label: "Second target")
        )
        harness.model.handleVolumeAction(.up)

        #expect(harness.model.targetPresentationState.value == nil)
        await waitUntil { harness.model.relayState == .active }
        #expect(harness.model.targetPresentationState == .hidden)
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await secondTarget.appliedOperations == [.setVolume(45)] }
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 45)
        harness.cleanup()
    }

    @Test("Runtime presentation automatically hides after its configured duration")
    func runtimePresentationAutomaticallyHides() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(
                confirmationDisplayDuration: 0.05
            )
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.appliedOperations == [.setVolume(6)] }
        await waitUntil { harness.model.targetPresentationState == .hidden }

        #expect(harness.model.targetPresentationState == .hidden)
        harness.cleanup()
    }

    @Test("Overlay receives presentation and route state without target identity")
    func overlayReceivesRedactedPresentationContext() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let overlayPresenter = AppModelOverlayPresenterRecorder()
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "private-target-identity"),
            session: session,
            targetOverlayPresenter: overlayPresenter
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil {
            overlayPresenter.updates.contains { $0.presentationState.value?.confirmedVolume == 6 }
        }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))

        #expect(overlayPresenter.updates.last?.presentationState == .routeLost)
        #expect(overlayPresenter.updates.last?.activationRule == makeConfiguration(
            stableIdentifier: "private-target-identity"
        ).activationRule)
        #expect(!String(reflecting: overlayPresenter.updates).contains("private-target-identity"))
        harness.cleanup()
    }

    @Test("Target cancellation does not fail or tear down later command dispatch")
    func cancelledCommandKeepsDispatchAvailable() async {
        let target = CancellationThenSuccessTarget()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 1 }
        await waitUntil { harness.model.targetPresentationState == .hidden }
        #expect(harness.model.targetCommandsFailed == 0)
        #expect(harness.model.relayState == .active)

        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.appliedOperations == [.setVolume(6)] }
        #expect(harness.model.targetCommandsFailed == 0)
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 6)
        harness.cleanup()
    }

    @Test("Route mismatch suppresses physical command execution")
    func routeMismatchSuppressesCommand() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        harness.model.handleVolumeAction(.mute)
        await Task.yield()

        #expect(await target.appliedOperations.isEmpty)
        #expect(harness.model.commandsSuppressed == 1)
        #expect(harness.model.relayState == .dormant)
        #expect(harness.model.targetPresentationState == .routeLost)
        harness.cleanup()
    }

    @Test("Physical commands remain serialized and bounded")
    func commandsAreSerializedAndBounded() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let maximumPending = VolumeCommandQueuePolicy.default.maximumPendingCommands
        for _ in 0..<(maximumPending + 2) {
            harness.model.handleVolumeAction(.mute)
        }
        await waitUntilAsync { await target.applyCount == 1 }

        #expect(harness.model.commandsRecorded == maximumPending)
        #expect(harness.model.commandsSuppressed == 2)
        #expect(await target.maximumConcurrentApplyCount == 1)

        for expectedCount in 1...maximumPending {
            await target.releaseCurrentApply()
            if expectedCount < maximumPending {
                await waitUntilAsync {
                    await target.applyCount == expectedCount + 1
                }
            }
        }
        await waitUntil { harness.model.targetCommandsDispatched == maximumPending }

        #expect(await target.maximumConcurrentApplyCount == 1)
        harness.cleanup()
    }

    @Test("Sleep suppresses stale command completion")
    func sleepSuppressesStaleCompletion() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 1 }
        harness.routeObserver.sleep()
        await target.releaseCurrentApply()
        await Task.yield()

        #expect(harness.model.relayState == .dormant)
        #expect(harness.model.targetCommandsFailed == 0)
        #expect(harness.model.targetPresentationState == .suspended)
        harness.cleanup()
    }

    @Test("Command failures publish only coarse private diagnostics")
    func commandFailureDiagnosticsRemainPrivate() async {
        let sensitiveIdentifier = "secret-udn-1234"
        let target = FailingCommandTarget(stableIdentifier: sensitiveIdentifier)
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: sensitiveIdentifier),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntil { harness.model.relayState == .offline }

        let diagnostics = harness.model.diagnosticsSummary
        #expect(harness.model.targetCommandsFailed == 1)
        let isFailed: Bool
        if case .failed = harness.model.targetPresentationState {
            isFailed = true
        } else {
            isFailed = false
        }
        #expect(isFailed)
        #expect(diagnostics.contains("target_connection=local-network"))
        #expect(!diagnostics.contains(sensitiveIdentifier))
        #expect(!diagnostics.contains("timeout"))
        #expect(!diagnostics.contains("protocolFault"))
        harness.cleanup()
    }

    @Test("Command failures emit one privacy-safe accessibility announcement")
    func commandFailuresEmitOnePrivacySafeAccessibilityAnnouncement() async {
        let target = FailingCommandTarget(stableIdentifier: "secret-udn-1234")
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "secret-udn-1234"),
            session: session,
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntil { harness.model.relayState == .offline }
        try? await Task.sleep(for: .milliseconds(350))

        #expect(announcements.values == ["Volume control unavailable"])
        #expect(!announcements.values.joined().contains("secret-udn-1234"))
        harness.cleanup()
    }

    @Test("A recovered command failure receives a new announcement")
    func recoveredCommandFailureReceivesNewAnnouncement() async {
        let target = FailsTwiceCommandTarget()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.relayState == .offline }
        #expect(announcements.values == ["Volume control unavailable"])

        harness.networkPathObserver.publish(NetworkPathSnapshot(status: .unavailable))
        harness.networkPathObserver.publish(availableNetworkSnapshot())
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetCommandsFailed == 2 }

        #expect(announcements.values == [
            "Volume control unavailable",
            "Volume control unavailable",
        ])
        harness.cleanup()
    }

    @Test("Failure cancels a stale deferred volume announcement")
    func failureCancelsStaleDeferredVolumeAnnouncement() async {
        let target = SucceedsThenFailsCommandTarget()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(announcementInterval: 1),
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { announcements.values == ["Volume 60 percent"] }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.relayState == .offline }
        try? await Task.sleep(for: .milliseconds(1_100))

        #expect(announcements.values == [
            "Volume 60 percent",
            "Volume control unavailable",
        ])
        harness.cleanup()
    }

    @Test("Preview commands preserve synchronous recording behavior")
    func previewCommandsRemainSynchronous() async {
        let harness = makeHarness(
            configuration: makePreviewConfiguration(),
            session: nil
        )

        await waitUntil { harness.model.relayState == .active }
        for _ in 0..<20 {
            harness.model.handleVolumeAction(.mute)
        }

        #expect(harness.model.commandsRecorded == 20)
        #expect(harness.model.commandsSuppressed == 0)
        #expect(harness.model.targetCommandsDispatched == 0)
        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Rapid physical command execution preserves FIFO order and latest presentation")
    func commandOrderIsFIFO() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        harness.model.handleVolumeAction(.mute)
        harness.model.handleVolumeAction(.down)
        await waitUntilAsync { await target.appliedOperations.count == 3 }

        #expect(
            await target.appliedOperations == [
                .setVolume(6),
                .setMuted(true),
                .setVolume(5),
            ]
        )
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 5)
        harness.cleanup()
    }

    @Test("Held input release discards queued repeat commands")
    func heldInputReleaseDiscardsBacklog() async {
        let target = BlockingCommandTarget()
        let monitor = ControllableVolumeKeyMonitor()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            volumeKeyMonitor: monitor
        )

        await waitUntil { harness.model.relayState == .active }
        let timestamp = ProcessInfo.processInfo.systemUptime
        monitor.publish(
            VolumeKeyEvent(action: .up, phase: .pressed, isRepeat: false, timestamp: timestamp)
        )
        await waitUntilAsync { await target.applyCount == 1 }
        try? await Task.sleep(for: .milliseconds(500))
        monitor.publish(
            VolumeKeyEvent(
                action: .up,
                phase: .released,
                isRepeat: false,
                timestamp: timestamp + 0.97
            )
        )
        await target.releaseCurrentApply()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await target.applyCount == 1)
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 6)
        harness.cleanup()
    }

    @Test("Dispatch cancellation clears the active presentation and recovers")
    func dispatchCancellationRecoversAfterRouteGain() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.applyCount == 1 }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        #expect(harness.model.targetPresentationState == .routeLost)

        await target.releaseCurrentApply()
        harness.routeObserver.publish(makeRoute())
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.applyCount == 2 }
        await target.releaseCurrentApply()
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 6 }

        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Sequential commands retain each intermediate confirmed baseline")
    func sequentialCommandsPresentIntermediateConfirmations() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        harness.model.handleVolumeAction(.mute)
        harness.model.handleVolumeAction(.down)
        await waitUntilAsync { await target.applyCount == 1 }

        await target.releaseCurrentApply()
        await waitUntilAsync { await target.applyCount == 2 }
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 6)

        await target.releaseCurrentApply()
        await waitUntilAsync { await target.applyCount == 3 }
        #expect(harness.model.targetPresentationState.value?.isMuted == true)
        #expect(harness.model.targetPresentationState.value?.confirmedVolume == 6)

        await target.releaseCurrentApply()
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 5 }
        #expect(harness.model.targetPresentationState.value?.isMuted == true)
        harness.cleanup()
    }

    @Test("A slow command stays pending until its confirmation arrives")
    func slowPendingPresentationDoesNotDismiss() async {
        let target = BlockingCommandTarget()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(
                confirmationDisplayDuration: 0.05
            )
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntilAsync { await target.applyCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))

        if case .pendingBaseline = harness.model.targetPresentationState {
            #expect(Bool(true))
        } else {
            Issue.record("Expected an in-flight command to remain visible")
        }

        await target.releaseCurrentApply()
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 6 }
        await waitUntil { harness.model.targetPresentationState == .hidden }
        harness.cleanup()
    }

    @Test("Muted presentation announces only the confirmed mute state")
    func mutedPresentationAnnouncementIsAccurate() async {
        let target = AppModelTargetStub()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntil { harness.model.targetPresentationState.value?.isMuted == true }

        #expect(announcements.values == ["Muted"])
        harness.cleanup()
    }

    @Test("Same-value command results do not repeat accessibility announcements")
    func sameValuePresentationDoesNotRepeatAnnouncement() async {
        let target = AppModelTargetStub(
            initialState: MediaTargetVolumeState(
                absoluteVolume: 100,
                isMuted: false,
                minimumVolume: 0,
                maximumVolume: 100,
                volumeStep: 1
            )
        )
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(announcementInterval: 0),
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetCommandsDispatched == 1 }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetCommandsDispatched == 2 }

        #expect(announcements.values == ["Volume 100 percent"])
        harness.cleanup()
    }

    @Test("Rapid confirmed presentations emit the latest trailing announcement")
    func rapidConfirmedPresentationsCoalesceAccessibilityAnnouncements() async {
        let target = AppModelTargetStub()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(announcementInterval: 0.3),
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { announcements.values == ["Volume 60 percent"] }

        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 7 }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 8 }

        #expect(announcements.values == ["Volume 60 percent"])
        await waitUntil {
            announcements.values == ["Volume 60 percent", "Volume 80 percent"]
        }
        harness.cleanup()
    }

    @Test("Presentation invalidation cancels a deferred accessibility announcement")
    func presentationInvalidationCancelsDeferredAccessibilityAnnouncement() async {
        let target = AppModelTargetStub()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(announcementInterval: 0.3),
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { announcements.values == ["Volume 60 percent"] }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 7 }

        harness.routeObserver.sleep()
        await waitUntil { harness.model.targetPresentationState == .suspended }
        try? await Task.sleep(for: .milliseconds(350))

        #expect(announcements.values == ["Volume 60 percent"])
        harness.cleanup()
    }

    @Test("Repeated rail confirmations dismiss after the latest command")
    func repeatedRailPresentationDismisses() async {
        let target = AppModelTargetStub(
            initialState: MediaTargetVolumeState(
                absoluteVolume: 100,
                isMuted: false,
                minimumVolume: 0,
                maximumVolume: 100,
                volumeStep: 1
            )
        )
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            targetPresentationTiming: MediaTargetPresentationTiming(
                confirmationDisplayDuration: 0.1
            )
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetPresentationState.value?.confirmedVolume == 100 }
        try? await Task.sleep(for: .milliseconds(50))

        harness.model.handleVolumeAction(.up)
        await waitUntil { harness.model.targetCommandsDispatched == 2 }
        try? await Task.sleep(for: .milliseconds(60))

        #expect(harness.model.targetPresentationState.isVisible)
        await waitUntil { harness.model.targetPresentationState == .hidden }
        harness.cleanup()
    }

    @Test("Route gain and wake hide presentation until a fresh probe completes")
    func routeGainAndWakeStartWithHiddenPresentation() async {
        let target = AppModelTargetStub()
        let announcements = AnnouncementRecorder()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            announcementRecorder: announcements
        )

        await waitUntil { harness.model.relayState == .active }
        harness.routeObserver.publish(makeRoute(name: "Different Output"))
        #expect(harness.model.targetPresentationState == .routeLost)

        harness.routeObserver.publish(makeRoute())
        await waitUntil { harness.model.relayState == .active }
        #expect(harness.model.targetPresentationState == .hidden)

        harness.routeObserver.sleep()
        harness.routeObserver.wake(makeRoute())
        await waitUntil { harness.model.relayState == .active }
        #expect(harness.model.targetPresentationState == .hidden)
        #expect(announcements.values.isEmpty)
        harness.cleanup()
    }

    @Test("Repeated dormant route snapshots do not churn the presentation epoch")
    func dormantRouteSnapshotsDoNotChurnPresentationEpoch() async {
        let target = AppModelTargetStub()
        let session = MediaTargetSession(target: target, invalidateResolution: { _ in })
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session
        )

        await waitUntil { harness.model.relayState == .active }
        let dormantRoute = makeRoute(name: "Different Output")
        harness.routeObserver.publish(dormantRoute)
        let dormantEpoch = harness.model.presentationInvalidationEpoch
        harness.routeObserver.publish(dormantRoute)
        harness.routeObserver.publish(dormantRoute)

        #expect(harness.model.relayState == .dormant)
        #expect(harness.model.presentationInvalidationEpoch == dormantEpoch)
        harness.cleanup()
    }

    @Test("Event tap failure cancels in-flight physical commands")
    func eventTapFailureCancelsCommand() async {
        let target = BlockingCommandTarget()
        let monitor = FlakyVolumeKeyMonitor()
        let session = MediaTargetSession(
            target: target,
            invalidateResolution: { _ in }
        )
        let harness = makeHarness(
            configuration: makeConfiguration(stableIdentifier: "fixture-target"),
            session: session,
            volumeKeyMonitor: monitor
        )

        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 1 }
        monitor.shouldFail = true
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .needsPermission }
        await target.releaseCurrentApply()
        await Task.yield()

        #expect(harness.model.relayState == .needsPermission)
        #expect(harness.model.targetCommandsFailed == 0)

        monitor.shouldFail = false
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)
        await waitUntilAsync { await target.applyCount == 2 }
        await target.releaseCurrentApply()
        await waitUntil { harness.model.targetCommandsDispatched == 2 }

        #expect(harness.model.relayState == .active)
        #expect(harness.model.targetCommandsFailed == 0)
        harness.cleanup()
    }

    @Test("Preview target recovers after event tap failure")
    func previewRecoversAfterEventTapFailure() async {
        let monitor = FlakyVolumeKeyMonitor()
        let harness = makeHarness(
            configuration: makePreviewConfiguration(),
            session: nil,
            volumeKeyMonitor: monitor
        )

        await waitUntil { harness.model.relayState == .active }
        monitor.shouldFail = true
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .needsPermission }

        monitor.shouldFail = false
        harness.applicationNotificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await waitUntil { harness.model.relayState == .active }
        harness.model.handleVolumeAction(.mute)

        #expect(harness.model.commandsRecorded == 1)
        #expect(harness.model.commandsSuppressed == 0)
        #expect(harness.model.targetCommandsDispatched == 0)
        harness.cleanup()
    }

    @Test("Explicit discovery selection persists only generic target metadata")
    func discoverySelectionPersistsConfiguration() {
        let harness = makeHarness(configuration: nil, session: nil)
        let choice = MediaTargetDiscoveryChoice(
            id: "fixture-private-id",
            label: "Media Renderer 1"
        )

        harness.model.selectDiscoveredTarget(choice)

        let stored = RelayConfigurationStore(defaults: harness.defaults).load()
        #expect(stored?.target.kind == .upnpMediaRenderer)
        #expect(stored?.target.name == "UPnP Media Target")
        #expect(stored?.target.stableIdentifier == "fixture-private-id")
        #expect(stored?.activationRule.audioOutputMatch == "Fixture Output")
        #expect(!harness.model.diagnosticsSummary.contains("fixture-private-id"))
        harness.cleanup()
    }

    @Test("Discovery selection preserves choices until the route is usable")
    func discoverySelectionRequiresRoute() async {
        let choice = MediaTargetDiscoveryChoice(
            id: "fixture-private-id",
            label: "Media Renderer 1"
        )
        let discovery = MediaTargetDiscoveryModel {
            [
                UPnPMediaTargetDiscoveryCandidate(
                    identity: MediaTargetIdentity(stableIdentifier: choice.id),
                    ordinal: 1
                ),
            ]
        }
        let harness = makeHarness(
            configuration: nil,
            session: nil,
            discovery: discovery
        )
        discovery.startScan()
        await waitUntil {
            if case .results = discovery.state { return true }
            return false
        }
        harness.routeObserver.publish(RouteSnapshot(audioOutput: nil, displays: []))

        harness.model.selectDiscoveredTarget(choice)

        #expect(RelayConfigurationStore(defaults: harness.defaults).load() == nil)
        #expect(harness.model.discovery.state == .routeUnavailable([choice]))

        harness.routeObserver.publish(makeRoute())
        #expect(harness.model.discovery.state == .results([choice]))

        harness.model.selectDiscoveredTarget(choice)
        #expect(RelayConfigurationStore(defaults: harness.defaults).load() != nil)
        harness.cleanup()
    }
}

@MainActor
private struct AppModelHarness {
    let model: RelayAppModel
    let routeObserver: AppModelRouteObserver
    let networkPathObserver: AppModelNetworkPathObserver
    let applicationNotificationCenter: NotificationCenter
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class AnnouncementRecorder {
    private(set) var values: [String] = []

    func post(_ value: String) {
        values.append(value)
    }
}

@MainActor
private func makeHarness(
    configuration: RelayConfiguration?,
    session: MediaTargetSession?,
    volumeKeyMonitor: any VolumeKeyMonitoring = InactiveVolumeKeyMonitor(),
    discovery: MediaTargetDiscoveryModel = MediaTargetDiscoveryModel(),
    initialNetworkSnapshot: NetworkPathSnapshot? = nil,
    targetPresentationTiming: MediaTargetPresentationTiming = MediaTargetPresentationTiming(),
    targetOverlayPresenter: any TargetOverlayPresenting = InactiveTargetOverlayPresenter(),
    announcementRecorder: AnnouncementRecorder? = nil,
    sessionFactory: ((RelayConfiguration?) -> MediaTargetSession?)? = nil
) -> AppModelHarness {
    let suiteName = "com.shinycomputers.media-control-relay.app-model-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let configurationStore = RelayConfigurationStore(defaults: defaults)
    if let configuration {
        configurationStore.save(configuration)
    }
    let routeObserver = AppModelRouteObserver(initialSnapshot: makeRoute())
    let networkPathObserver = AppModelNetworkPathObserver(
        initialSnapshot: initialNetworkSnapshot
    )
    let applicationNotificationCenter = NotificationCenter()
    let model = RelayAppModel(
        routeObserver: routeObserver,
        networkPathObserver: networkPathObserver,
        configurationStore: configurationStore,
        volumeKeyMonitor: volumeKeyMonitor,
        inputMonitoringAccess: InputMonitoringAccessClient(
            preflight: { true },
            request: {}
        ),
        applicationNotificationCenter: applicationNotificationCenter,
        discovery: discovery,
        targetPresentationTiming: targetPresentationTiming,
        targetOverlayPresenter: targetOverlayPresenter,
        postAccessibilityAnnouncement: { announcement in
            announcementRecorder?.post(announcement)
        },
        mediaTargetSessionFactory: { configuration in
            sessionFactory?(configuration) ?? session
        }
    )
    return AppModelHarness(
        model: model,
        routeObserver: routeObserver,
        networkPathObserver: networkPathObserver,
        applicationNotificationCenter: applicationNotificationCenter,
        defaults: defaults,
        suiteName: suiteName
    )
}

@MainActor
private final class AppModelNetworkPathObserver: NetworkPathObserving {
    var onSnapshot: ((NetworkPathSnapshot) -> Void)?

    private let initialSnapshot: NetworkPathSnapshot?
    private(set) var currentSnapshot: NetworkPathSnapshot?

    init(initialSnapshot: NetworkPathSnapshot?) {
        self.initialSnapshot = initialSnapshot
        currentSnapshot = initialSnapshot
    }

    func start() {
        if let initialSnapshot {
            onSnapshot?(initialSnapshot)
        }
    }

    func stop() {}

    func refresh() -> NetworkPathSnapshot? {
        guard let currentSnapshot else {
            return nil
        }
        onSnapshot?(currentSnapshot)
        return currentSnapshot
    }

    func publish(_ snapshot: NetworkPathSnapshot) {
        guard snapshot != currentSnapshot else {
            return
        }
        currentSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    func setCurrentSnapshotWithoutPublishing(_ snapshot: NetworkPathSnapshot) {
        currentSnapshot = snapshot
    }
}

@MainActor
private final class FlakyVolumeKeyMonitor: VolumeKeyMonitoring {
    let events = AsyncStream<VolumeKeyEvent> { continuation in
        continuation.finish()
    }
    var shouldFail = false

    func start() throws {
        if shouldFail {
            throw VolumeKeyMonitorError.eventTapUnavailable
        }
    }

    func stop() {}
}

@MainActor
private final class ControllableVolumeKeyMonitor: VolumeKeyMonitoring {
    let events: AsyncStream<VolumeKeyEvent>
    private let continuation: AsyncStream<VolumeKeyEvent>.Continuation

    init() {
        let stream = AsyncStream<VolumeKeyEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }

    func start() throws {}

    func stop() {
        continuation.finish()
    }

    func publish(_ event: VolumeKeyEvent) {
        continuation.yield(event)
    }
}

@MainActor
private final class AppModelRouteObserver: RouteObserving {
    var onSnapshot: ((RouteSnapshot) -> Void)?
    var onStateChange: ((RouteObservationState) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private(set) var state: RouteObservationState = .stopped
    private let initialSnapshot: RouteSnapshot

    init(initialSnapshot: RouteSnapshot) {
        self.initialSnapshot = initialSnapshot
    }

    func start() {
        state = .observing
        onStateChange?(state)
        onSnapshot?(initialSnapshot)
    }

    func stop() {
        state = .stopped
        onStateChange?(state)
    }

    func publish(_ snapshot: RouteSnapshot) {
        onSnapshot?(snapshot)
    }

    func sleep() {
        state = .suspended
        onStateChange?(state)
        onSleep?()
    }

    func wake(_ snapshot: RouteSnapshot) {
        state = .observing
        onStateChange?(state)
        onSnapshot?(snapshot)
        onWake?()
    }
}

@MainActor
private final class AppModelOverlayPresenterRecorder: TargetOverlayPresenting {
    struct Update: Equatable {
        let presentationState: MediaTargetPresentationState
        let routeSnapshot: RouteSnapshot
        let activationRule: ActivationRule?
    }

    private(set) var updates: [Update] = []

    func update(
        presentationState: MediaTargetPresentationState,
        routeSnapshot: RouteSnapshot,
        activationRule: ActivationRule?
    ) {
        updates.append(Update(
            presentationState: presentationState,
            routeSnapshot: routeSnapshot,
            activationRule: activationRule
        ))
    }
}

private actor AppModelTargetStub: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState: MediaTargetVolumeState
    private(set) var readCount = 0
    private(set) var appliedOperations: [MediaTargetVolumeOperation] = []

    init(initialState: MediaTargetVolumeState = makeVolumeState()) {
        currentState = initialState
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        return currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        appliedOperations.append(operation)
        currentState = applying(operation, to: currentState)
        return currentState
    }
}

private actor CancellationThenSuccessTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeVolumeState()
    private(set) var applyCount = 0
    private(set) var appliedOperations: [MediaTargetVolumeOperation] = []

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyCount += 1
        if applyCount == 1 {
            throw .cancelled
        }
        appliedOperations.append(operation)
        currentState = applying(operation, to: currentState)
        return currentState
    }
}

private actor BlockingCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeVolumeState()
    private var continuation: CheckedContinuation<Void, Never>?
    private var concurrentApplyCount = 0
    private(set) var applyCount = 0
    private(set) var maximumConcurrentApplyCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyCount += 1
        concurrentApplyCount += 1
        maximumConcurrentApplyCount = max(
            maximumConcurrentApplyCount,
            concurrentApplyCount
        )
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        concurrentApplyCount -= 1
        currentState = applying(operation, to: currentState)
        return currentState
    }

    func releaseCurrentApply() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private actor FailingCommandTarget: MediaVolumeTarget {
    nonisolated let identity: MediaTargetIdentity

    init(stableIdentifier: String) {
        identity = MediaTargetIdentity(stableIdentifier: stableIdentifier)
    }

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .timeout
    }
}

private actor SucceedsThenFailsCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeVolumeState()
    private(set) var applyCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyCount += 1
        guard applyCount == 1 else {
            throw .timeout
        }
        currentState = applying(operation, to: currentState)
        return currentState
    }
}

private actor FailsTwiceCommandTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private var currentState = makeVolumeState()
    private(set) var applyCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        currentState
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        applyCount += 1
        guard applyCount > 2 else {
            throw .timeout
        }
        currentState = applying(operation, to: currentState)
        return currentState
    }
}

private actor AuthenticationRejectedAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .authenticationRejected
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .authenticationRejected
    }
}

private actor RetryingAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if readCount == 1 {
            throw .offline
        }
        return makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor LocalNetworkRetryingAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if readCount == 1 {
            throw .localNetworkDenied
        }
        return makeVolumeState()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor BlockingAppModelTarget: MediaVolumeTarget {
    nonisolated let identity = MediaTargetIdentity(stableIdentifier: "fixture-target")

    private(set) var readCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func readState() async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        readCount += 1
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }
        return makeVolumeState()
    }

    func releaseRead() {
        released = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }

    func apply(
        _ operation: MediaTargetVolumeOperation
    ) async throws(MediaTargetFailure) -> MediaTargetVolumeState {
        throw .capabilityUnavailable
    }
}

private actor AppModelInvalidationRecorder {
    private(set) var reasons: [MediaTargetSessionInvalidation] = []

    func record(_ reason: MediaTargetSessionInvalidation) {
        reasons.append(reason)
    }
}

private func makeConfiguration(stableIdentifier: String?) -> RelayConfiguration {
    RelayConfiguration(
        target: RelayTargetMetadata(
            kind: .upnpMediaRenderer,
            name: "UPnP Media Target",
            stableIdentifier: stableIdentifier
        ),
        activationRule: ActivationRule(
            audioOutputMatch: "Fixture Output",
            requiresDisplay: false
        )
    )
}

private func makePreviewConfiguration() -> RelayConfiguration {
    RelayConfiguration(
        target: RelayTargetMetadata(
            kind: .preview,
            name: "Preview Target"
        ),
        activationRule: ActivationRule(
            audioOutputMatch: "Fixture Output",
            requiresDisplay: false
        )
    )
}

private func makeRoute(name: String = "Fixture Output") -> RouteSnapshot {
    RouteSnapshot(
        audioOutput: AudioOutputSnapshot(
            name: name,
            transportKind: .display
        ),
        displays: []
    )
}

private func availableNetworkSnapshot() -> NetworkPathSnapshot {
    NetworkPathSnapshot(
        status: .available,
        interfaceKinds: [.wifi],
        supportsIPv4: true
    )
}

private func makeVolumeState() -> MediaTargetVolumeState {
    MediaTargetVolumeState(
        absoluteVolume: 5,
        isMuted: false,
        minimumVolume: 0,
        maximumVolume: 10
    )
}

private func applying(
    _ operation: MediaTargetVolumeOperation,
    to state: MediaTargetVolumeState
) -> MediaTargetVolumeState {
    switch operation {
    case let .setVolume(volume):
        return MediaTargetVolumeState(
            absoluteVolume: volume,
            isMuted: state.isMuted,
            minimumVolume: state.minimumVolume,
            maximumVolume: state.maximumVolume
        )
    case let .setMuted(isMuted):
        return MediaTargetVolumeState(
            absoluteVolume: state.absoluteVolume,
            isMuted: isMuted,
            minimumVolume: state.minimumVolume,
            maximumVolume: state.maximumVolume
        )
    }
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<100 {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for app-model state")
}

private func waitUntilAsync(
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<100 {
        if await condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for asynchronous app-model state")
}
