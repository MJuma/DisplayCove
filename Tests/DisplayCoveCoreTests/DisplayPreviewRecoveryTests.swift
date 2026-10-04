@testable import DisplayCoveCore
import ScreenCaptureKit
import XCTest

final class DisplayPreviewRecoveryTests: XCTestCase {
    func testClassifiesExplicitUserStop() {
        XCTAssertEqual(
            DisplayPreviewRecovery.stopReason(for: error(.userStopped)),
            .userStopped
        )
    }

    func testClassifiesPermissionDenial() {
        XCTAssertEqual(
            DisplayPreviewRecovery.stopReason(for: error(.userDeclined)),
            .permissionRequired
        )
    }

    func testClassifiesSystemStopAsRecoverable() {
        XCTAssertEqual(
            DisplayPreviewRecovery.stopReason(for: error(.systemStoppedStream)),
            .recoverable
        )
    }

    func testClassifiesUnsupportedCaptureAsFailed() {
        XCTAssertEqual(
            DisplayPreviewRecovery.stopReason(for: error(.notSupported)),
            .failed
        )
    }

    func testUsesBoundedBackoff() {
        XCTAssertEqual(DisplayPreviewRecovery.retryDelay(for: 1), .milliseconds(500))
        XCTAssertEqual(DisplayPreviewRecovery.retryDelay(for: 2), .seconds(1))
        XCTAssertEqual(DisplayPreviewRecovery.retryDelay(for: 3), .seconds(2))
        XCTAssertEqual(DisplayPreviewRecovery.retryDelay(for: 9), .seconds(2))
    }

    private func error(_ code: SCStreamError.Code) -> NSError {
        NSError(
            domain: SCStreamErrorDomain,
            code: code.rawValue
        )
    }
}
