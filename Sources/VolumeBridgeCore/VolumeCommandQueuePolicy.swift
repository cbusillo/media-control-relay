import Foundation

public struct VolumeCommandQueuePolicy: Equatable, Sendable {
    public let maximumPendingCommands: Int
    public let maximumBatchSize: Int
    public let initialRepeatDelay: TimeInterval
    public let releaseDebounce: TimeInterval
    public let duplicateEventWindow: TimeInterval
    public let maximumRepeatTicks: Int

    public init(
        maximumPendingCommands: Int = 18,
        maximumBatchSize: Int = 6,
        initialRepeatDelay: TimeInterval = 0.45,
        releaseDebounce: TimeInterval = 0.12,
        duplicateEventWindow: TimeInterval = 0.15,
        maximumRepeatTicks: Int = 24
    ) {
        self.maximumPendingCommands = max(1, maximumPendingCommands)
        self.maximumBatchSize = max(1, maximumBatchSize)
        self.initialRepeatDelay = max(0, initialRepeatDelay)
        self.releaseDebounce = max(0, releaseDebounce)
        self.duplicateEventWindow = max(0, duplicateEventWindow)
        self.maximumRepeatTicks = max(0, maximumRepeatTicks)
    }

    public static let `default` = VolumeCommandQueuePolicy()

    public func canEnqueue(pendingCount: Int, adding count: Int = 1) -> Bool {
        pendingCount >= 0 &&
            count > 0 &&
            pendingCount + count <= maximumPendingCommands
    }

    public func repeatDelay(afterCompletedTicks repeatCount: Int) -> TimeInterval? {
        guard repeatCount >= 0, repeatCount < maximumRepeatTicks else {
            return nil
        }
        if repeatCount == 0 {
            return initialRepeatDelay
        }
        let multiplier: Double
        if repeatCount < 4 {
            multiplier = 2.0 / 3.0
        } else if repeatCount < 10 {
            multiplier = 8.0 / 15.0
        } else {
            multiplier = 4.0 / 9.0
        }
        return min(initialRepeatDelay, max(0.05, initialRepeatDelay * multiplier))
    }

    public func shouldRepeat(_ action: VolumeAction) -> Bool {
        action.supportsHoldRepeat && maximumRepeatTicks > 0
    }

    public func boundedBatchSize(requestedCount: Int, pendingCount: Int) -> Int {
        guard requestedCount > 0, pendingCount >= 0 else {
            return 0
        }
        let availableCapacity = max(0, maximumPendingCommands - pendingCount)
        return min(requestedCount, maximumBatchSize, availableCapacity)
    }

    public func isDuplicateEvent(
        previousTimestamp: TimeInterval,
        currentTimestamp: TimeInterval
    ) -> Bool {
        let elapsed = currentTimestamp - previousTimestamp
        return elapsed >= 0 && elapsed <= duplicateEventWindow
    }

    public func isReleaseSettled(
        releaseTimestamp: TimeInterval,
        currentTimestamp: TimeInterval
    ) -> Bool {
        currentTimestamp - releaseTimestamp >= releaseDebounce
    }
}
