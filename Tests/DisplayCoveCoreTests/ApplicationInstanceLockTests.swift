@testable import DisplayCoveCore
import Foundation
import XCTest

final class ApplicationInstanceLockTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("displaycove-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testLockExcludesAnotherOwnerAndReleasesWithoutDeletingTheFile() throws {
        let root = try fixture()
        let path = root.appendingPathComponent("app.lock")
        var owner = try ApplicationInstanceLock.acquire(at: path)
        XCTAssertNotNil(owner)
        let contender = try withExtendedLifetime(owner) {
            try ApplicationInstanceLock.acquire(at: path)
        }
        XCTAssertNil(contender)
        owner = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertNotNil(try ApplicationInstanceLock.acquire(at: path))
    }

    func testIndependentBundleLocksDoNotConflict() throws {
        let root = try fixture()
        let first = try ApplicationInstanceLock.acquire(at: root.appendingPathComponent("production.lock"))
        let second = try ApplicationInstanceLock.acquire(at: root.appendingPathComponent("integration.lock"))
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        withExtendedLifetime((first, second)) {}
    }

    func testSymlinkAndDirectoryAreRejected() throws {
        let root = try fixture()
        let target = root.appendingPathComponent("target")
        try Data().write(to: target)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ApplicationInstanceLock.acquire(at: link))
        XCTAssertThrowsError(try ApplicationInstanceLock.acquire(at: root))
    }
}
