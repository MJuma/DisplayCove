import CoreGraphics
@testable import DisplayCoveCore
import XCTest

final class WindowResizeGeometryTests: XCTestCase {
    private let nativeResolution = CGSize(width: 1920, height: 1080)
    private let snappingThreshold: CGFloat = 30

    func testSnapsWhenWidthApproachesNativeResolution() {
        let snappedSize = WindowResizeGeometry.snappedContentSize(
            proposedContentSize: CGSize(width: 1900, height: 1068.75),
            nativeResolution: nativeResolution,
            snappingThreshold: snappingThreshold
        )

        XCTAssertEqual(snappedSize, nativeResolution)
    }

    func testSnapsWhenHeightApproachesNativeResolution() {
        let snappedSize = WindowResizeGeometry.snappedContentSize(
            proposedContentSize: CGSize(width: 1870, height: 1055),
            nativeResolution: nativeResolution,
            snappingThreshold: snappingThreshold
        )

        XCTAssertEqual(snappedSize, nativeResolution)
    }

    func testDoesNotSnapWhenNeitherDimensionIsNearNativeResolution() {
        let snappedSize = WindowResizeGeometry.snappedContentSize(
            proposedContentSize: CGSize(width: 1280, height: 720),
            nativeResolution: nativeResolution,
            snappingThreshold: snappingThreshold
        )

        XCTAssertNil(snappedSize)
    }

    func testRejectsInvalidGeometry() {
        XCTAssertNil(WindowResizeGeometry.snappedContentSize(
            proposedContentSize: .zero,
            nativeResolution: nativeResolution,
            snappingThreshold: snappingThreshold
        ))
        XCTAssertNil(WindowResizeGeometry.snappedContentSize(
            proposedContentSize: nativeResolution,
            nativeResolution: nativeResolution,
            snappingThreshold: -1
        ))
    }
}
