import Foundation

@MainActor
final class PreferencesStorage<Value: Codable> {
    private let defaults: UserDefaults
    private let key: String
    private let initialValue: Value
    private let persistsChanges: Bool
    private var preservesUnreadableData = false
    private(set) var issue: String?

    init(defaults: UserDefaults, key: String, initialValue: Value, persistsChanges: Bool) {
        self.defaults = defaults
        self.key = key
        self.initialValue = initialValue
        self.persistsChanges = persistsChanges
    }

    func load() -> Value {
        guard persistsChanges, let object = defaults.object(forKey: key) else {
            return initialValue
        }
        let preferenceKey = key
        do {
            guard let data = object as? Data else {
                throw PreferencesReadError()
            }
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            preservesUnreadableData = true
            issue = "Saved settings could not be loaded. The original data is preserved. " +
                "Changes apply only to this session until you reset saved settings."
            AppLog.preferences.error(
                "Could not load \(preferenceKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return initialValue
        }
    }

    func save(_ value: Value) -> String? {
        guard persistsChanges, !preservesUnreadableData else {
            return issue
        }
        let preferenceKey = key
        do {
            try defaults.set(JSONEncoder().encode(value), forKey: key)
            issue = nil
        } catch {
            issue = "Settings could not be saved: \(error.localizedDescription)"
            AppLog.preferences.error("Could not save \(preferenceKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return issue
    }

    func reset() {
        preservesUnreadableData = false
        issue = nil
    }
}

private struct PreferencesReadError: LocalizedError {
    var errorDescription: String? {
        "The saved settings are not encoded data."
    }
}
