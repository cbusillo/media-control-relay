import Foundation
import Testing

/// Absolute-path domains keep the preferences daemon's plist inside a disposable test directory.
final class IsolatedUserDefaults {
    let directory: URL
    let domain: String
    let defaults: UserDefaults
    private var cleanedUp = false

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCRDefaults-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        domain = directory.appendingPathComponent("preferences").path
        defaults = try #require(UserDefaults(suiteName: domain))
    }

    func tearDown() throws {
        guard !cleanedUp else { return }
        defaults.removePersistentDomain(forName: domain)
        // Flush the preferences daemon before deleting the directory to prevent a late empty plist.
        defaults.synchronize()
        try FileManager.default.removeItem(at: directory)
        cleanedUp = true
    }

    deinit {
        do {
            try tearDown()
        } catch {
            Issue.record(error, "Unable to remove test preferences directory")
        }
    }
}
