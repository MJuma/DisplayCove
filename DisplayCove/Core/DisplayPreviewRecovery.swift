import Foundation
import ScreenCaptureKit

enum DisplayPreviewState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case pausedByUser
    case reconnecting(attempt: Int)
    case permissionRequired
    case failed(String)

    var expectsFrames: Bool {
        switch self {
        case .reconnecting, .running, .starting:
            true
        case .failed, .pausedByUser, .permissionRequired, .stopped:
            false
        }
    }
}

enum DisplayPreviewStopReason: Equatable, Sendable {
    case userStopped
    case permissionRequired
    case recoverable
    case failed
}

enum DisplayPreviewRecovery {
    static let maxAutomaticRetryAttempts = 3

    static func stopReason(for error: Error) -> DisplayPreviewStopReason {
        let error = error as NSError
        guard
            error.domain == SCStreamErrorDomain,
            let code = SCStreamError.Code(rawValue: error.code)
        else {
            return .recoverable
        }

        return switch code {
        case .userStopped:
            .userStopped
        case .userDeclined:
            .permissionRequired
        case
            .failedApplicationConnectionInvalid,
            .failedApplicationConnectionInterrupted,
            .failedToStart,
            .internalError,
            .noCaptureSource,
            .systemStoppedStream:
            .recoverable
        case .invalidParameter, .missingEntitlements, .notSupported:
            .failed
        default:
            .recoverable
        }
    }

    static func retryDelay(for attempt: Int) -> Duration {
        switch attempt {
        case ...1:
            .milliseconds(500)
        case 2:
            .seconds(1)
        default:
            .seconds(2)
        }
    }
}
