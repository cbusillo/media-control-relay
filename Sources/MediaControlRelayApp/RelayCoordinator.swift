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

    func apply(_ event: RelayRoutingEvent) {
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
        if let command = output.command {
            if previewSink.send(command) == .recorded {
                previewSink.completePendingCommand()
            }
        } else if case .volumeAction = event {
            previewSink.recordSuppressedCommand()
        }

        configuration = reducer.configuration
        relayState = output.resolvedState
        activationMatches = output.activationMatches
        recordedCommands = previewSink.recordedCommands
        recordedCommandCount = previewSink.recordedCommandCount
        suppressedCommandCount = previewSink.suppressedCommandCount
    }
}
