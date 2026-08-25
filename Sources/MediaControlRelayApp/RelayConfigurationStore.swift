import Foundation
import MediaControlCore

struct RelayConfigurationStore {
    let defaults: UserDefaults
    let key = "relayConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RelayConfiguration? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(RelayConfiguration.self, from: data)
    }

    func save(_ configuration: RelayConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
