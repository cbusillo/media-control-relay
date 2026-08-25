import Testing
@testable import MediaControlCore

@Suite("Preview command sink")
struct RelayRecordingPreviewSinkTests {
    @Test("Records commands in order and tracks counters")
    func orderAndCounters() {
        var sink = RelayRecordingPreviewSink(
            policy: VolumeCommandQueuePolicy(maximumPendingCommands: 3)
        )
        #expect(sink.send(RelayCommand(sequence: 1, action: .up)) == .recorded)
        sink.completePendingCommand()
        #expect(sink.send(RelayCommand(sequence: 2, action: .down)) == .recorded)
        sink.completePendingCommand()
        #expect(sink.recordedCommands.map(\.sequence) == [1, 2])
        #expect(sink.recordedCommandCount == 2)
        #expect(sink.suppressedCommandCount == 0)
        #expect(sink.pendingCount == 0)
    }

    @Test("Backpressure bounds a burst and suppresses later commands")
    func backpressure() {
        var sink = RelayRecordingPreviewSink(
            policy: VolumeCommandQueuePolicy(maximumPendingCommands: 2)
        )
        #expect(sink.send(RelayCommand(sequence: 1, action: .up)) == .recorded)
        #expect(sink.send(RelayCommand(sequence: 2, action: .up)) == .recorded)
        #expect(sink.send(RelayCommand(sequence: 3, action: .up)) == .suppressed)
        #expect(sink.recordedCommandCount == 2)
        #expect(sink.suppressedCommandCount == 1)
        #expect(sink.pendingCount == 2)
    }

    @Test("Cancellation drops pending capacity without erasing recorded history")
    func cancellation() {
        var sink = RelayRecordingPreviewSink(
            policy: VolumeCommandQueuePolicy(maximumPendingCommands: 2)
        )
        _ = sink.send(RelayCommand(sequence: 1, action: .mute))
        sink.cancelPending()

        #expect(sink.pendingCount == 0)
        #expect(sink.recordedCommandCount == 1)
        #expect(sink.send(RelayCommand(sequence: 2, action: .down)) == .recorded)
        #expect(sink.recordedCommands.map(\.sequence) == [1, 2])
    }

    @Test("Recorded history remains bounded while the total count grows")
    func boundedHistory() {
        var sink = RelayRecordingPreviewSink(
            policy: VolumeCommandQueuePolicy(maximumPendingCommands: 2)
        )

        for sequence in 1 ... 4 {
            #expect(
                sink.send(RelayCommand(sequence: sequence, action: .up)) == .recorded
            )
            sink.completePendingCommand()
        }

        #expect(sink.recordedCommandCount == 4)
        #expect(sink.recordedCommands.map(\.sequence) == [3, 4])
        #expect(sink.pendingCount == 0)
    }

    @Test("Inactive routing can record a suppressed command without queueing")
    func explicitSuppression() {
        var sink = RelayRecordingPreviewSink()
        sink.recordSuppressedCommand()

        #expect(sink.suppressedCommandCount == 1)
        #expect(sink.pendingCount == 0)
        #expect(sink.recordedCommandCount == 0)
    }
}
