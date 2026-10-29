import Darwin
import Foundation

final class ApplicationInstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    static func acquire(at url: URL) throws -> ApplicationInstanceLock? {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw InstanceLockError(message: "Could not open the instance lock (errno \(errno)).")
        }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFREG
        else {
            close(descriptor)
            throw InstanceLockError(message: "The instance lock is not a regular file.")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK {
                return nil
            }
            throw InstanceLockError(message: "Could not acquire the instance lock (errno \(code)).")
        }
        return ApplicationInstanceLock(descriptor: descriptor)
    }

    static func claimApplication() throws -> ApplicationInstanceLock? {
        guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty,
              identifier.utf8.count <= 200,
              identifier.utf8.allSatisfy({
                  (65 ... 90).contains($0) || (97 ... 122).contains($0) ||
                      (48 ... 57).contains($0) || [45, 46, 95].contains($0)
              })
        else {
            throw InstanceLockError(message: "The application has no valid bundle identifier.")
        }
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("DisplayCove/Instances", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return try acquire(at: directory.appendingPathComponent("\(identifier).lock"))
    }
}

private struct InstanceLockError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
