import AVFoundation
import Cocoa
import ScreenCaptureKit

enum DisplayRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case displayUnavailable
    case microphonePermissionDenied
    case unsupportedCodec
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "This DisplayCove display is already recording."
        case .notRecording:
            "This DisplayCove display is not recording."
        case .displayUnavailable:
            "The virtual display is not available for recording."
        case .microphonePermissionDenied:
            "Microphone access is required to record microphone audio."
        case .unsupportedCodec:
            "The selected video codec is not supported."
        case .unsupportedFileType:
            "QuickTime recording is not supported on this Mac."
        }
    }
}

@MainActor
final class DisplayRecordingController: NSObject {
    enum State {
        case idle
        case preparing
        case recording
        case finishing
    }

    var onStateChanged: ((State) -> Void)?
    var onDurationChanged: ((TimeInterval) -> Void)?
    var onFinished: ((URL) -> Void)?
    var onFailure: ((Error) -> Void)?

    private(set) var state: State = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    var isActive: Bool {
        state != .idle
    }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var durationTimer: Timer?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    func start(
        displayID: CGDirectDisplayID,
        screenConfiguration: ScreenConfigurationSnapshot,
        outputURL: URL,
        settings: RecordingSettings
    ) async throws {
        guard state == .idle else {
            throw DisplayRecordingError.alreadyRecording
        }

        if settings.capturesMicrophone {
            guard await requestMicrophoneAccess() else {
                throw DisplayRecordingError.microphonePermissionDenied
            }
        }

        state = .preparing

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let display = shareableContent.displays.first(where: {
                $0.displayID == displayID
            }) else {
                throw DisplayRecordingError.displayUnavailable
            }

            let sourceSize = CGSize(
                width: screenConfiguration.resolution.width * screenConfiguration.scaleFactor,
                height: screenConfiguration.resolution.height * screenConfiguration.scaleFactor
            )
            guard let outputSize = settings.quality.outputSize(for: sourceSize) else {
                throw DisplayRecordingError.displayUnavailable
            }

            let streamConfiguration = SCStreamConfiguration()
            streamConfiguration.width = Int(outputSize.width)
            streamConfiguration.height = Int(outputSize.height)
            streamConfiguration.minimumFrameInterval = CMTime(
                value: 1,
                timescale: CMTimeScale(settings.frameRate.rawValue)
            )
            streamConfiguration.queueDepth = 8
            streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
            streamConfiguration.showsCursor = settings.showsCursor
            streamConfiguration.showMouseClicks = settings.showsMouseClicks
            streamConfiguration.scalesToFit = true
            streamConfiguration.capturesAudio = settings.capturesSystemAudio
            streamConfiguration.sampleRate = 48000
            streamConfiguration.channelCount = 2
            streamConfiguration.excludesCurrentProcessAudio = true
            streamConfiguration.captureMicrophone = settings.capturesMicrophone
            streamConfiguration.microphoneCaptureDeviceID = settings.microphoneDeviceID

            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = outputURL
            recordingConfiguration.videoCodecType = settings.codec.avVideoCodecType
            recordingConfiguration.outputFileType = .mov
            recordingConfiguration.mixesAudioWithMicrophone = true

            guard recordingConfiguration.availableVideoCodecTypes.contains(
                settings.codec.avVideoCodecType
            ) else {
                throw DisplayRecordingError.unsupportedCodec
            }
            guard recordingConfiguration.availableOutputFileTypes.contains(.mov) else {
                throw DisplayRecordingError.unsupportedFileType
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let stream = SCStream(
                filter: filter,
                configuration: streamConfiguration,
                delegate: self
            )
            let recordingOutput = SCRecordingOutput(
                configuration: recordingConfiguration,
                delegate: self
            )

            try stream.addRecordingOutput(recordingOutput)

            self.stream = stream
            self.recordingOutput = recordingOutput
            self.outputURL = outputURL

            try await stream.startCapture()
        } catch {
            await cleanUpAfterFailure(error, notify: false)
            throw error
        }
    }

    func stop() async throws -> URL {
        guard state != .idle else {
            throw DisplayRecordingError.notRecording
        }
        guard let stream, let recordingOutput else {
            throw DisplayRecordingError.notRecording
        }

        state = .finishing
        durationTimer?.invalidate()
        durationTimer = nil

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation

            do {
                try stream.removeRecordingOutput(recordingOutput)
            } catch {
                stopContinuation = nil
                continuation.resume(throwing: error)
                Task {
                    await cleanUpAfterFailure(error, notify: false)
                }
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    let recordingOutput
                else {
                    return
                }

                let duration = recordingOutput.recordedDuration.seconds
                guard duration.isFinite, duration >= 0 else {
                    return
                }

                onDurationChanged?(duration)
            }
        }
    }

    private func finishSuccessfully() async {
        guard let outputURL else {
            await cleanUpAfterFailure(DisplayRecordingError.displayUnavailable)
            return
        }

        if let stream {
            try? await stream.stopCapture()
        }

        durationTimer?.invalidate()
        durationTimer = nil
        stream = nil
        recordingOutput = nil
        self.outputURL = nil
        state = .idle

        stopContinuation?.resume(returning: outputURL)
        stopContinuation = nil
        onFinished?(outputURL)
    }

    private func cleanUpAfterFailure(
        _ error: Error,
        notify: Bool = true
    ) async {
        durationTimer?.invalidate()
        durationTimer = nil

        if let stream {
            try? await stream.stopCapture()
        }

        stream = nil
        recordingOutput = nil
        outputURL = nil
        state = .idle

        stopContinuation?.resume(throwing: error)
        stopContinuation = nil
        if notify {
            onFailure?(error)
        }
    }
}

extension DisplayRecordingController: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            state = .recording
            startDurationTimer()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            await self?.finishSuccessfully()
        }
    }

    nonisolated func recordingOutput(
        _: SCRecordingOutput,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            await self?.cleanUpAfterFailure(error)
        }
    }
}

extension DisplayRecordingController: SCStreamDelegate {
    nonisolated func stream(_: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, state != .idle else {
                return
            }

            await cleanUpAfterFailure(error)
        }
    }
}

private extension RecordingCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264:
            .h264
        case .hevc:
            .hevc
        }
    }
}
