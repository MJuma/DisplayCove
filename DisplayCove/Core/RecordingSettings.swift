import CoreGraphics
import Foundation

enum RecordingCodec: String, CaseIterable, Codable, Sendable {
    case h264
    case hevc

    var displayName: String {
        switch self {
        case .h264:
            "H.264"
        case .hevc:
            "HEVC"
        }
    }
}

enum RecordingFrameRate: Int, CaseIterable, Codable, Sendable {
    case thirty = 30
    case sixty = 60

    var displayName: String {
        "Up to \(rawValue) fps"
    }
}

enum RecordingQuality: String, CaseIterable, Codable, Sendable {
    case native
    case high
    case compact

    var displayName: String {
        switch self {
        case .native:
            "Native Resolution"
        case .high:
            "High (up to 1080p)"
        case .compact:
            "Compact (up to 720p)"
        }
    }

    func outputSize(for sourceSize: CGSize) -> CGSize? {
        guard
            sourceSize.width.isFinite,
            sourceSize.height.isFinite,
            sourceSize.width > 0,
            sourceSize.height > 0
        else {
            return nil
        }

        let maximumSize: CGSize = switch self {
        case .native:
            sourceSize
        case .high:
            sourceSize.width >= sourceSize.height
                ? CGSize(width: 1920, height: 1080)
                : CGSize(width: 1080, height: 1920)
        case .compact:
            sourceSize.width >= sourceSize.height
                ? CGSize(width: 1280, height: 720)
                : CGSize(width: 720, height: 1280)
        }

        let scale = min(
            1,
            maximumSize.width / sourceSize.width,
            maximumSize.height / sourceSize.height
        )

        return CGSize(
            width: max(2, floor(sourceSize.width * scale / 2) * 2),
            height: max(2, floor(sourceSize.height * scale / 2) * 2)
        )
    }
}

struct RecordingSettings: Codable, Equatable, Sendable {
    var codec: RecordingCodec = .h264
    var frameRate: RecordingFrameRate = .thirty
    var quality: RecordingQuality = .native
    var showsCursor = true
    var showsMouseClicks = false
    var capturesSystemAudio = false
    var capturesMicrophone = false
    var microphoneDeviceID: String?
}
