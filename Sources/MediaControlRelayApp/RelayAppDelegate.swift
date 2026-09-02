import AppKit
import MediaControlCore

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    private static let maximumPendingActionCount = 16
    private static let maximumPendingRejectedURLCount = 16

    private weak var model: RelayAppModel?
    private var pendingActions: [VolumeAction] = []
    private var pendingRejectedURLCount = 0

    var pendingActionCount: Int {
        pendingActions.count
    }

    func attach(model: RelayAppModel) {
        self.model = model

        if pendingRejectedURLCount > 0 {
            model.recordRejectedExternalVolumeURL(count: pendingRejectedURLCount)
            pendingRejectedURLCount = 0
        }

        let actions = pendingActions
        pendingActions.removeAll(keepingCapacity: true)
        actions.forEach(model.handleExternalVolumeAction)
    }

    func receive(urls: [URL]) {
        for url in urls {
            guard let action = ExternalVolumeActionURLParser.action(for: url) else {
                if let model {
                    model.recordRejectedExternalVolumeURL()
                } else {
                    recordPendingRejection()
                }
                continue
            }

            if let model {
                model.handleExternalVolumeAction(action)
            } else if pendingActions.count < Self.maximumPendingActionCount {
                pendingActions.append(action)
            } else {
                recordPendingRejection()
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

    private func recordPendingRejection() {
        pendingRejectedURLCount = min(
            Self.maximumPendingRejectedURLCount,
            pendingRejectedURLCount + 1
        )
    }
}
