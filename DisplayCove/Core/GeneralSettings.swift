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

    private enum CodingKeys: String, CodingKey {
        case defaultResolution, bringsWindowToFront, showsPreviewCursor, preservesPhysicalHDR
    }
}

extension GeneralSettings {
    init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.defaultResolution) {
            defaultResolution = try values.decode(DisplayResolution.self, forKey: .defaultResolution)
            guard defaultResolution.width > 0, defaultResolution.height > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .defaultResolution, in: values,
                    debugDescription: "The saved resolution must have positive dimensions."
                )
            }
        }
        if values.contains(.bringsWindowToFront) {
            bringsWindowToFront = try values.decode(Bool.self, forKey: .bringsWindowToFront)
        }
        if values.contains(.showsPreviewCursor) {
            showsPreviewCursor = try values.decode(Bool.self, forKey: .showsPreviewCursor)
        }
        if values.contains(.preservesPhysicalHDR) {
            preservesPhysicalHDR = try values.decode(Bool.self, forKey: .preservesPhysicalHDR)
        }
    }
}

@MainActor
@Observable
final class GeneralPreferences {
    static let shared = GeneralPreferences()

    private let storage: PreferencesStorage<GeneralSettings>
    private(set) var persistenceError: String?

    var settings: GeneralSettings {
        didSet {
            persistenceError = storage.save(settings)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = "generalSettings",
        persistsChanges: Bool = true
    ) {
        storage = PreferencesStorage(
            defaults: defaults, key: key, initialValue: GeneralSettings(),
            persistsChanges: persistsChanges
        )
        settings = storage.load()
        persistenceError = storage.issue
    }

    func resetSavedSettings() {
        storage.reset()
        settings = GeneralSettings()
    }
}
