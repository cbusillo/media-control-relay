import Foundation
import Testing
@testable import Media_Control_Relay

struct IsolatedUserDefaultsTests {
    @MainActor
    @Test func welcomeStateUsesTestHostPreferences() throws {
        let app = RelayApp()
        let original = app.hasShownWelcome
        defer { app.hasShownWelcome = original }
        app.hasShownWelcome = !original
        #expect(RelayApp().hasShownWelcome == !original)
        let stored = try #require(
            RelayApp.testHostPreferences.persistentDomain(
                forName: RelayApp.testHostPreferencesDomain
            )
        )
        #expect(stored.values.contains { ($0 as? Bool) == !original })
    }

    @MainActor
    @Test func testHostPreferencesPersistWithBuildProducts() throws {
        let domain = RelayApp.testHostPreferencesDomain
        let products = Bundle.main.bundleURL.deletingLastPathComponent().path
        #expect(domain.hasPrefix(products + "/"))
        let defaults = RelayApp.testHostPreferences
        let key = UUID().uuidString
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        defer {
            defaults.removeObject(forKey: key)
            defaults.synchronize()
        }
        #expect(defaults.synchronize())
        let plist = URL(fileURLWithPath: domain).appendingPathExtension("plist")
        let stored = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
                as? [String: Any]
        )
        #expect(stored[key] as? String == value)
    }

    @Test func persistenceAndTeardown() throws {
        let fixture = try IsolatedUserDefaults()
        let key = UUID().uuidString
        let value = UUID().uuidString
        fixture.defaults.set(value, forKey: key)
        #expect(fixture.defaults.synchronize())

        let plist = URL(fileURLWithPath: fixture.domain).appendingPathExtension("plist")
        let stored = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
                as? [String: Any]
        )
        #expect(stored[key] as? String == value)
        #expect(UserDefaults(suiteName: fixture.domain)?.string(forKey: key) == value)

        try fixture.tearDown()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(fixture.defaults.object(forKey: key) == nil)
        try fixture.tearDown()
    }

    @Test func independentFixtures() throws {
        let first = try IsolatedUserDefaults()
        let second = try IsolatedUserDefaults()
        let key = UUID().uuidString
        first.defaults.set(true, forKey: key)
        #expect(second.defaults.object(forKey: key) == nil)
    }

    @Test func scopeExitRemovesDirectory() throws {
        let directory: URL
        do {
            let fixture = try IsolatedUserDefaults()
            directory = fixture.directory
            fixture.defaults.set(true, forKey: UUID().uuidString)
            #expect(fixture.defaults.synchronize())
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
