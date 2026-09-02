import AppKit
import MediaControlCore

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    private static let maximumPendingActionCount = 16
    private static let maximumPendingRemoteActionCount = 16
    private static let maximumPendingRejectedURLCount = 16

    private weak var model: RelayAppModel?
    private var pendingActions: [VolumeAction] = []
    private var pendingRemoteActions: [MediaRemoteAction] = []
    private var pendingRejectedURLCount = 0
    private var pendingRejectedRemoteURLCount = 0
    private var terminationDeferred = false

    var pendingActionCount: Int {
        pendingActions.count
    }

    var pendingRemoteActionCount: Int {
        pendingRemoteActions.count
    }

    func attach(model: RelayAppModel) {
        self.model = model

        if pendingRejectedURLCount > 0 {
            model.recordRejectedExternalVolumeURL(count: pendingRejectedURLCount)
            pendingRejectedURLCount = 0
        }
        if pendingRejectedRemoteURLCount > 0 {
            model.recordRejectedExternalRemoteURL(count: pendingRejectedRemoteURLCount)
            pendingRejectedRemoteURLCount = 0
        }

        let actions = pendingActions
        pendingActions.removeAll(keepingCapacity: true)
        actions.forEach(model.handleExternalVolumeAction)
        let remoteActions = pendingRemoteActions
        pendingRemoteActions.removeAll(keepingCapacity: true)
        remoteActions.forEach(model.handleExternalRemoteAction)
    }

    func receive(urls: [URL]) {
        for url in urls {
            switch ExternalControlURLRouter.route(for: url) {
            case let .activeOutputVolume(action):
                if let model {
                    model.handleExternalVolumeAction(action)
                } else if pendingActions.count < Self.maximumPendingActionCount {
                    pendingActions.append(action)
                } else {
                    recordPendingRejection()
                }
            case let .remote(action):
                if let model {
                    model.handleExternalRemoteAction(action)
                } else if pendingRemoteActions.count < Self.maximumPendingRemoteActionCount {
                    pendingRemoteActions.append(action)
                } else {
                    pendingRejectedRemoteURLCount = min(
                        Self.maximumPendingRejectedURLCount,
                        pendingRejectedRemoteURLCount + 1
                    )
                }
            case .rejected:
                if url.host == "remote" {
                    if let model {
                        model.recordRejectedExternalRemoteURL()
                    } else {
                        pendingRejectedRemoteURLCount = min(
                            Self.maximumPendingRejectedURLCount,
                            pendingRejectedRemoteURLCount + 1
                        )
                    }
                } else if let model {
                    model.recordRejectedExternalVolumeURL()
                } else {
                    recordPendingRejection()
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls: urls)
    }

    func applicationShouldHandleReopen(
        _ application: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationDeferred,
              let stop = model?.remoteControlTerminationStopper else {
            return .terminateNow
        }
        terminationDeferred = true
        Task.detached(priority: .userInitiated) {
            stop()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    private func recordPendingRejection() {
        pendingRejectedURLCount = min(
            Self.maximumPendingRejectedURLCount,
            pendingRejectedURLCount + 1
        )
    }
}
