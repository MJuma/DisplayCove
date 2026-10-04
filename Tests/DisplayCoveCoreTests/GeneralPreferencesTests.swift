@testable import DisplayCoveCore
import Foundation
import XCTest

@MainActor
final class GeneralPreferencesTests: XCTestCase {
    func testPreferencesPersistSettings() throws {
        let suiteName = "GeneralPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = GeneralPreferences(defaults: defaults)
        preferences.settings = GeneralSettings(
            defaultResolution: DisplayResolution(width: 2560, height: 1440),
            bringsWindowToFront: false,
            showsPreviewCursor: false,
            preservesPhysicalHDR: false
        )

        XCTAssertEqual(
            GeneralPreferences(defaults: defaults).settings,
            preferences.settings
        )
    }
}
