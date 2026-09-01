import AppKit
import MediaControlCore

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
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
                    pendingRejectedURLCount += 1
                }
                continue
            }

            if let model {
                model.handleExternalVolumeAction(action)
            } else {
                pendingActions.append(action)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls: urls)
    }
}
