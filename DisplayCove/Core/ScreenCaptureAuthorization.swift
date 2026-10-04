import Foundation
import ScreenCaptureKit

enum ScreenCaptureAuthorizationError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "macOS did not finish restarting Screen Recording access. Quit DisplayCove and open it again."
        }
    }
}

enum ScreenCaptureAuthorization {
    static func verify() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let gate = ScreenCaptureAuthorizationGate()

            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            ) { content, error in
                gate.complete {
                    if let error {
                        continuation.resume(throwing: error)
                    } else if content != nil {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                            throwing: ScreenCaptureAuthorizationError.timedOut
                        )
                    }
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                gate.complete {
                    continuation.resume(
                        throwing: ScreenCaptureAuthorizationError.timedOut
                    )
                }
            }
        }
    }
}

private final class ScreenCaptureAuthorizationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false

    func complete(_ action: () -> Void) {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        isComplete = true
        lock.unlock()
        action()
    }
}
