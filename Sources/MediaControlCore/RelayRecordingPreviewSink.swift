import Foundation

public enum RelayCommandRecordingResult: Equatable, Sendable {
    case recorded
    case suppressed
}

public struct RelayRecordingPreviewSink: Sendable {
    public let policy: VolumeCommandQueuePolicy
    public private(set) var recordedCommands: [RelayCommand] = []
    public private(set) var suppressedCommandCount = 0

    private var totalRecordedCommandCount = 0
    private var pendingCommandCount = 0

    public init(policy: VolumeCommandQueuePolicy = .default) {
        self.policy = policy
    }

    public var recordedCommandCount: Int {
        totalRecordedCommandCount
    }

    public var pendingCount: Int {
        pendingCommandCount
    }

    public mutating func send(_ command: RelayCommand) -> RelayCommandRecordingResult {
        guard policy.canEnqueue(pendingCount: pendingCommandCount) else {
            suppressedCommandCount += 1
            return .suppressed
        }

        recordedCommands.append(command)
        if recordedCommands.count > policy.maximumPendingCommands {
            recordedCommands.removeFirst(
                recordedCommands.count - policy.maximumPendingCommands
            )
        }
        totalRecordedCommandCount += 1
        pendingCommandCount += 1
        return .recorded
    }

    public mutating func completePendingCommand() {
        pendingCommandCount = max(0, pendingCommandCount - 1)
    }

    public mutating func recordSuppressedCommand() {
        suppressedCommandCount += 1
    }

    public mutating func cancelPending() {
        pendingCommandCount = 0
    }

    public mutating func reset() {
        recordedCommands.removeAll()
        totalRecordedCommandCount = 0
        suppressedCommandCount = 0
        pendingCommandCount = 0
    }
}
