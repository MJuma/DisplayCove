import Foundation
import Observation

@MainActor
@Observable
final class RecordingPreferences {
    static let shared = RecordingPreferences()

    private let defaults: UserDefaults
    private let key: String

    var settings: RecordingSettings {
        didSet {
            persist()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = "recordingSettings"
    ) {
        self.defaults = defaults
        self.key = key

        if
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(RecordingSettings.self, from: data)
        {
            self.settings = settings
        } else {
            settings = RecordingSettings()
        }
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(settings), forKey: key)
        } catch {
            AppLog.preferences.error(
                "Could not save recording settings: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
