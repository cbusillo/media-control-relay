import Foundation

public struct VolumeKeyGestureTracker: Sendable {
    public let policy: VolumeCommandQueuePolicy

    private var heldAction: VolumeAction?
    private var releaseTimestamp: TimeInterval?
    private var nextRepeatTimestamp: TimeInterval?
    private var completedRepeatTicks = 0
    private var lastInitialPress: (action: VolumeAction, timestamp: TimeInterval)?

    public init(policy: VolumeCommandQueuePolicy = .default) {
        self.policy = policy
    }

    public var nextDeadline: TimeInterval? {
        if let releaseTimestamp {
            return releaseTimestamp + policy.releaseDebounce
        }
        return nextRepeatTimestamp
    }

    public mutating func ingest(
        _ event: VolumeKeyEvent,
        pendingCount: Int = 0
    ) -> [VolumeAction] {
        switch event.phase {
        case .pressed:
            guard !event.isRepeat else {
                return []
            }
            if let lastInitialPress,
               lastInitialPress.action == event.action,
               policy.isDuplicateEvent(
                   previousTimestamp: lastInitialPress.timestamp,
                   currentTimestamp: event.timestamp
               ) {
                return []
            }

            self.lastInitialPress = (event.action, event.timestamp)
            releaseTimestamp = nil
            completedRepeatTicks = 0
            if policy.shouldRepeat(event.action) {
                heldAction = event.action
                nextRepeatTimestamp = event.timestamp + policy.initialRepeatDelay
            } else {
                heldAction = nil
                nextRepeatTimestamp = nil
            }
            return policy.canEnqueue(pendingCount: pendingCount) ? [event.action] : []

        case .released:
            if lastInitialPress?.action == event.action {
                lastInitialPress = nil
            }
            guard heldAction == event.action else {
                return []
            }
            releaseTimestamp = event.timestamp
            nextRepeatTimestamp = nil
            return []
        }
    }

    public mutating func tick(
        at timestamp: TimeInterval,
        pendingCount: Int = 0
    ) -> [VolumeAction] {
        if let releaseTimestamp {
            guard policy.isReleaseSettled(
                releaseTimestamp: releaseTimestamp,
                currentTimestamp: timestamp
            ) else {
                return []
            }
            resetHold()
            return []
        }

        guard let heldAction,
              let nextRepeatTimestamp,
              timestamp >= nextRepeatTimestamp else {
            return []
        }

        completedRepeatTicks += 1
        let shouldEmit = policy.canEnqueue(pendingCount: pendingCount)
        if let delay = policy.repeatDelay(afterCompletedTicks: completedRepeatTicks) {
            self.nextRepeatTimestamp = timestamp + delay
        } else {
            resetHold()
        }
        return shouldEmit ? [heldAction] : []
    }

    public mutating func cancelHold() {
        resetHold()
    }

    private mutating func resetHold() {
        heldAction = nil
        releaseTimestamp = nil
        nextRepeatTimestamp = nil
        completedRepeatTicks = 0
        lastInitialPress = nil
    }
}
