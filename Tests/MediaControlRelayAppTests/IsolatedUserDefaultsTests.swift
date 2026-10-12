import Foundation
import Testing

struct IsolatedUserDefaultsTests {
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
