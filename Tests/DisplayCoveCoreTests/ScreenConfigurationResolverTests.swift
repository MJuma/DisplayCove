import AppKit
@testable import DisplayCoveCore
import XCTest

final class ScreenConfigurationResolverTests: XCTestCase {
    func testResolvesMatchingDisplayConfiguration() {
        let screens = [
            TestScreen(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                backingScaleFactor: 2
            ),
            TestScreen(
                displayID: 2,
                frame: CGRect(x: 1920, y: 0, width: 1280, height: 720),
                backingScaleFactor: 1
            ),
        ]

        let configuration = ScreenConfigurationResolver.configuration(
            for: 2,
            screens: screens
        )

        XCTAssertEqual(configuration, ScreenConfigurationSnapshot(
            resolution: CGSize(width: 1280, height: 720),
            scaleFactor: 1
        ))
    }

    func testReturnsNilWhenDisplayIsMissing() {
        let screens = [
            TestScreen(
                displayID: nil,
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                backingScaleFactor: 2
            ),
        ]

        XCTAssertNil(ScreenConfigurationResolver.configuration(
            for: 1,
            screens: screens
        ))
    }
}

private struct TestScreen: ScreenConfigurationProviding {
    let displayID: CGDirectDisplayID?
    let frame: CGRect
    let backingScaleFactor: CGFloat
}
