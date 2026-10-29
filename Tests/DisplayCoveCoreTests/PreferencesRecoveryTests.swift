@testable import DisplayCoveCore
import Foundation
import XCTest

@MainActor
final class PreferencesRecoveryTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "PreferencesRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testOlderGeneralSettingsKeepSavedValuesAndDefaultOnlyMissingFields() throws {
        let defaults = try defaults()
        defaults.set(Data("""
        {"defaultResolution":{"width":1280,"height":720},"bringsWindowToFront":false}
        """.utf8), forKey: "generalSettings")
        let preferences = GeneralPreferences(defaults: defaults)
        XCTAssertEqual(preferences.settings.defaultResolution, DisplayResolution(width: 1280, height: 720))
        XCTAssertFalse(preferences.settings.bringsWindowToFront)
        XCTAssertTrue(preferences.settings.showsPreviewCursor)
        XCTAssertTrue(preferences.settings.preservesPhysicalHDR)
        XCTAssertNil(preferences.persistenceError)
    }

    func testOlderRecordingSettingsKeepSavedValuesWithoutEnablingAudio() throws {
        let defaults = try defaults()
        defaults.set(Data("""
        {"codec":"hevc","quality":"compact","showsCursor":false}
        """.utf8), forKey: "recordingSettings")
        let preferences = RecordingPreferences(defaults: defaults)
        XCTAssertEqual(preferences.settings.codec, .hevc)
        XCTAssertEqual(preferences.settings.quality, .compact)
        XCTAssertFalse(preferences.settings.showsCursor)
        XCTAssertEqual(preferences.settings.frameRate, .thirty)
        XCTAssertFalse(preferences.settings.capturesSystemAudio)
        XCTAssertFalse(preferences.settings.capturesMicrophone)
        XCTAssertNil(preferences.persistenceError)
    }

    func testCorruptGeneralSettingsSurviveSessionEditsUntilExplicitReset() throws {
        let defaults = try defaults()
        let original = Data("{invalid".utf8)
        defaults.set(original, forKey: "generalSettings")
        let preferences = GeneralPreferences(defaults: defaults)
        XCTAssertNotNil(preferences.persistenceError)
        preferences.settings.showsPreviewCursor = false
        XCTAssertEqual(defaults.data(forKey: "generalSettings"), original)
        XCTAssertNotNil(GeneralPreferences(defaults: defaults).persistenceError)
        preferences.resetSavedSettings()
        XCTAssertNil(preferences.persistenceError)
        XCTAssertEqual(GeneralPreferences(defaults: defaults).settings, GeneralSettings())
    }

    func testUnsupportedRecordingSettingsSurviveSessionEditsUntilExplicitReset() throws {
        let defaults = try defaults()
        let original = Data(#"{"codec":"future-codec"}"#.utf8)
        defaults.set(original, forKey: "recordingSettings")
        let preferences = RecordingPreferences(defaults: defaults)
        XCTAssertNotNil(preferences.persistenceError)
        preferences.settings.quality = .compact
        XCTAssertEqual(defaults.data(forKey: "recordingSettings"), original)
        preferences.resetSavedSettings()
        XCTAssertNil(preferences.persistenceError)
        XCTAssertEqual(RecordingPreferences(defaults: defaults).settings, RecordingSettings())
    }

    func testWrongStorageTypeIsPreserved() throws {
        let defaults = try defaults()
        defaults.set("unreadable original", forKey: "recordingSettings")
        let preferences = RecordingPreferences(defaults: defaults)
        preferences.settings.codec = .hevc
        XCTAssertNotNil(preferences.persistenceError)
        XCTAssertEqual(defaults.string(forKey: "recordingSettings"), "unreadable original")
    }

    func testInvalidPresentFieldsAreNotTreatedAsMissing() throws {
        for json in [
            #"{"defaultResolution":{"width":0,"height":720}}"#,
            #"{"bringsWindowToFront":null}"#,
            #"{"showsPreviewCursor":"false"}"#,
        ] {
            let defaults = try defaults()
            let data = Data(json.utf8)
            defaults.set(data, forKey: "generalSettings")
            let preferences = GeneralPreferences(defaults: defaults)
            XCTAssertNotNil(preferences.persistenceError)
            preferences.settings.preservesPhysicalHDR = false
            XCTAssertEqual(defaults.data(forKey: "generalSettings"), data)
        }
    }

    func testTransientPreferencesNeverReadOrOverwriteSavedSettings() throws {
        let defaults = try defaults()
        let original = Data("invalid saved data".utf8)
        defaults.set(original, forKey: "generalSettings")
        defaults.set(original, forKey: "recordingSettings")
        let general = GeneralPreferences(defaults: defaults, persistsChanges: false)
        let recording = RecordingPreferences(defaults: defaults, persistsChanges: false)
        XCTAssertNil(general.persistenceError)
        XCTAssertNil(recording.persistenceError)
        general.settings.bringsWindowToFront = false
        recording.settings.codec = .hevc
        general.resetSavedSettings()
        recording.resetSavedSettings()
        XCTAssertEqual(defaults.data(forKey: "generalSettings"), original)
        XCTAssertEqual(defaults.data(forKey: "recordingSettings"), original)
    }
}
