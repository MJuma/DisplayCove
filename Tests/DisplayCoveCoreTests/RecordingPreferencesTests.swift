@testable import DisplayCoveCore
import Foundation
import XCTest

@MainActor
final class RecordingPreferencesTests: XCTestCase {
    func testPreferencesPersistSettings() throws {
        let suiteName = "RecordingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = RecordingPreferences(defaults: defaults)
        preferences.settings = RecordingSettings(
            codec: .hevc,
            frameRate: .sixty,
            quality: .high,
            showsCursor: false,
            showsMouseClicks: true,
            capturesSystemAudio: true,
            capturesMicrophone: true,
            microphoneDeviceID: "microphone"
        )

        XCTAssertEqual(
            RecordingPreferences(defaults: defaults).settings,
            preferences.settings
        )
    }
}
