import Observation
import MediaControlCore

@MainActor
@Observable
final class RelayCoordinator {
    private(set) var relayState: RelayState = .unconfigured
    private(set) var activationMatches = false
    private(set) var recordedCommandCount = 0
    private(set) var suppressedCommandCount = 0
    private(set) var recordedCommands: [RelayCommand] = []

    private(set) var configuration: RelayConfiguration?

    private var reducer: RelayRoutingReducer
    private var previewSink: RelayRecordingPreviewSink
    private let cancelHeldGesture: @MainActor () -> Void

    init(
        configuration: RelayConfiguration?,
        cancelHeldGesture: @escaping @MainActor () -> Void
    ) {
        self.configuration = configuration
        self.reducer = RelayRoutingReducer(configuration: configuration)
        self.previewSink = RelayRecordingPreviewSink()
        self.cancelHeldGesture = cancelHeldGesture
    }

    @discardableResult
    func apply(_ event: RelayRoutingEvent) -> RelayCommand? {
        if case .configuration = event {
            previewSink.reset()
        }

        let output = reducer.reduce(
            event,
            pendingCommandCount: previewSink.pendingCount
        )
        if output.cancelHeldGesture {
            cancelHeldGesture()
        }
        if output.cancelPendingCommand {
            previewSink.cancelPending()
        }
        let recordedCommand: RelayCommand?
        if let command = output.command {
            switch previewSink.send(command) {
            case .recorded:
                recordedCommand = command
            case .suppressed:
                recordedCommand = nil
            }
        } else if case .volumeAction = event {
            previewSink.recordSuppressedCommand()
            recordedCommand = nil
        } else {
            recordedCommand = nil
        }

        publish(output)
        return recordedCommand
    }

    func completeCommand() {
        previewSink.completePendingCommand()
        publishCounters()
    }

    func cancelPendingCommands() {
        previewSink.cancelPending()
        publishCounters()
    }

    private func publish(_ output: RelayRoutingOutput) {
        configuration = reducer.configuration
        relayState = output.resolvedState
        activationMatches = output.activationMatches
        publishCounters()
    }

    private func publishCounters() {
        recordedCommands = previewSink.recordedCommands
        recordedCommandCount = previewSink.recordedCommandCount
        suppressedCommandCount = previewSink.suppressedCommandCount
    }
}
