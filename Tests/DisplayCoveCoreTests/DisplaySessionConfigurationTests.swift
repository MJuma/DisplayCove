import CoreGraphics
@testable import DisplayCoveCore
import XCTest

final class DisplaySessionConfigurationTests: XCTestCase {
    func testStandardConfigurationRetainsUltrawideHiDPIProfile() {
        let configuration = DisplaySessionConfiguration.standard()

        XCTAssertEqual(configuration.maxPixelWidth, 5120)
        XCTAssertEqual(configuration.maxPixelHeight, 2160)
        XCTAssertTrue(configuration.isHiDPI)
        XCTAssertTrue(configuration.modes.contains {
            $0.width == 5120 && $0.height == 1440
        })
        XCTAssertTrue(configuration.modes.contains {
            $0.width == 3440 && $0.height == 1440
        })
    }

    func testStandardConfigurationUsesProvidedSerialNumber() {
        let configuration = DisplaySessionConfiguration.standard(serialNumber: 42)

        XCTAssertEqual(configuration.serialNumber, 42)
        XCTAssertEqual(configuration.name, "DisplayCove 42")
        XCTAssertEqual(configuration.productID, 0x0001)
        XCTAssertEqual(configuration.vendorID, 0x444356)
    }

    func testFirstDisplayUsesUnnumberedProductName() {
        XCTAssertEqual(
            DisplaySessionConfiguration.standard(serialNumber: 1).name,
            "DisplayCove"
        )
    }
}
