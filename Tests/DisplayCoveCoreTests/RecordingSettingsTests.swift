import CoreGraphics
@testable import DisplayCoveCore
import XCTest

final class RecordingSettingsTests: XCTestCase {
    func testNativeQualityPreservesEvenSourceDimensions() {
        XCTAssertEqual(
            RecordingQuality.native.outputSize(
                for: CGSize(width: 3840, height: 2160)
            ),
            CGSize(width: 3840, height: 2160)
        )
    }

    func testHighQualityScalesLandscapeTo1080p() {
        XCTAssertEqual(
            RecordingQuality.high.outputSize(
                for: CGSize(width: 5120, height: 2880)
            ),
            CGSize(width: 1920, height: 1080)
        )
    }

    func testCompactQualityPreservesPortraitAspectRatio() {
        XCTAssertEqual(
            RecordingQuality.compact.outputSize(
                for: CGSize(width: 1080, height: 1920)
            ),
            CGSize(width: 720, height: 1280)
        )
    }

    func testQualityRejectsInvalidSourceSize() {
        XCTAssertNil(RecordingQuality.native.outputSize(for: .zero))
    }
}
