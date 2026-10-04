@testable import DisplayCoveCore
import XCTest

final class DisplaySerialAllocatorTests: XCTestCase {
    func testClaimsSequentialSerialNumbers() {
        let allocator = DisplaySerialAllocator()

        XCTAssertEqual(allocator.claim(), 1)
        XCTAssertEqual(allocator.claim(), 2)
        XCTAssertEqual(allocator.claim(), 3)
    }

    func testReleasedSerialNumberCanBeReused() {
        let allocator = DisplaySerialAllocator()

        XCTAssertEqual(allocator.claim(), 1)
        XCTAssertEqual(allocator.claim(), 2)
        allocator.release(1)

        XCTAssertEqual(allocator.claim(), 1)
    }

    func testReturnsNilWhenRangeIsExhausted() {
        let allocator = DisplaySerialAllocator(availableSerials: 7 ... 8)

        XCTAssertEqual(allocator.claim(), 7)
        XCTAssertEqual(allocator.claim(), 8)
        XCTAssertNil(allocator.claim())
    }
}
