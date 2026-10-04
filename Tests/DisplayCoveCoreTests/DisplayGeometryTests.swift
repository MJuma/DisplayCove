import CoreGraphics
@testable import DisplayCoveCore
import XCTest

final class DisplayGeometryTests: XCTestCase {
    func testMapsViewPointToDisplayCoordinates() {
        let point = DisplayGeometry.displayPoint(
            from: CGPoint(x: 400, y: 150),
            viewSize: CGSize(width: 800, height: 600),
            displayResolution: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(point, CGPoint(x: 960, y: 810))
    }

    func testRejectsInvalidGeometry() {
        XCTAssertNil(DisplayGeometry.displayPoint(
            from: .zero,
            viewSize: .zero,
            displayResolution: CGSize(width: 1920, height: 1080)
        ))
        XCTAssertNil(DisplayGeometry.displayPoint(
            from: CGPoint(x: CGFloat.infinity, y: 0),
            viewSize: CGSize(width: 800, height: 600),
            displayResolution: CGSize(width: 1920, height: 1080)
        ))
        XCTAssertNil(DisplayGeometry.displayPoint(
            from: .zero,
            viewSize: CGSize(width: 800, height: 600),
            displayResolution: CGSize(width: -1, height: 1080)
        ))
    }
}
