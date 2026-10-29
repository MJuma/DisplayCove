import Foundation
import Observation

@MainActor
@Observable
final class RecordingPreferences {
    static let shared = RecordingPreferences()

    private let storage: PreferencesStorage<RecordingSettings>
    private(set) var persistenceError: String?

    var settings: RecordingSettings {
        didSet {
            persistenceError = storage.save(settings)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = "recordingSettings",
        persistsChanges: Bool = true
    ) {
        storage = PreferencesStorage(
            defaults: defaults, key: key, initialValue: RecordingSettings(),
            persistsChanges: persistsChanges
        )
        settings = storage.load()
        persistenceError = storage.issue
    }

    func resetSavedSettings() {
        storage.reset()
        settings = RecordingSettings()
    }
}
