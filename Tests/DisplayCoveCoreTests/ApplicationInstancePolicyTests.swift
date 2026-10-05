@testable import DisplayCoveCore
import XCTest

final class ApplicationInstancePolicyTests: XCTestCase {
    func testOnlyProcessRemainsActive() {
        XCTAssertFalse(
            ApplicationInstancePolicy.shouldTerminate(
                currentProcessID: 100,
                matchingProcessIDs: [100]
            )
        )
    }

    func testNewerProcessTerminates() {
        XCTAssertTrue(
            ApplicationInstancePolicy.shouldTerminate(
                currentProcessID: 200,
                matchingProcessIDs: [100, 200]
            )
        )
    }

    func testOldestProcessRemainsActiveDuringSimultaneousLaunch() {
        XCTAssertFalse(
            ApplicationInstancePolicy.shouldTerminate(
                currentProcessID: 100,
                matchingProcessIDs: [200, 100]
            )
        )
    }
}
