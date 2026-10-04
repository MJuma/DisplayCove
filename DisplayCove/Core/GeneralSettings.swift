import Foundation
import Observation

struct DisplayResolution: Codable, Hashable, Sendable {
    let width: Int
    let height: Int

    var displayName: String {
        "\(width) × \(height)"
    }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    var defaultResolution = DisplayResolution(width: 1920, height: 1080)
    var bringsWindowToFront = true
    var showsPreviewCursor = true
    var preservesPhysicalHDR = true
}

@MainActor
@Observable
final class GeneralPreferences {
    static let shared = GeneralPreferences()

    private let defaults: UserDefaults
    private let key: String

    var settings: GeneralSettings {
        didSet {
            persist()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = "generalSettings"
    ) {
        self.defaults = defaults
        self.key = key

        if
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(GeneralSettings.self, from: data)
        {
            self.settings = settings
        } else {
            settings = GeneralSettings()
        }
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(settings), forKey: key)
        } catch {
            AppLog.preferences.error(
                "Could not save general settings: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
