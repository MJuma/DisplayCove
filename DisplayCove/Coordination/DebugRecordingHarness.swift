#if DEBUG
    import AVFoundation
    import Cocoa
    import Darwin

    @MainActor
    enum DebugRecordingHarness {
        static func startIfRequested(
            for displayWindow: ManagedDisplayWindow,
            coordinator: DisplayWindowCoordinator
        ) {
            let environment = ProcessInfo.processInfo.environment
            guard environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] != nil else {
                return
            }

            Task {
                var failure: (any Error)?
                do {
                    let settings = try settings(from: environment)
                    guard let duration = Double(environment["DISPLAYCOVE_RECORDING_TEST_DURATION"] ?? "2"),
                          duration.isFinite, (0.1 ... 30).contains(duration)
                    else {
                        throw DebugRecordingHarnessError.invalidConfiguration
                    }
                    try await Task.sleep(for: .seconds(1))
                    guard
                        let resolution = displayWindow.viewController.currentResolution,
                        let scaleFactor = displayWindow.viewController.displayScaleFactor,
                        let expectedVideoSize = settings.quality.outputSize(
                            for: CGSize(
                                width: CGFloat(resolution.width) * scaleFactor,
                                height: CGFloat(resolution.height) * scaleFactor
                            )
                        )
                    else {
                        throw DebugRecordingHarnessError.invalidOutput
                    }
                    try await displayWindow.viewController.startRecording(
                        to: DebugIntegrationEnvironment.recordingURL(),
                        settings: settings
                    )
                    try await Task.sleep(for: .seconds(max(0.1, duration)))
                    guard let outputURL =
                        try await displayWindow.viewController.stopRecording()
                    else {
                        throw DebugRecordingHarnessError.missingOutput
                    }
                    AppLog.recording.info(
                        "Debug recording completed: \(outputURL.path, privacy: .public)"
                    )
                    try await verifyMetadata(
                        at: outputURL,
                        settings: settings,
                        expectedVideoSize: expectedVideoSize
                    )
                    if environment["DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT"] != "1" {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                } catch {
                    failure = error
                }
                await coordinator.stopAll()
                DebugIntegrationEnvironment.finish(error: failure, recording: true)
            }
        }

        private static func settings(from environment: [String: String]) throws -> RecordingSettings {
            var settings = RecordingSettings()
            if let value = environment["DISPLAYCOVE_RECORDING_TEST_CODEC"] {
                guard let codec = RecordingCodec(rawValue: value) else {
                    throw DebugRecordingHarnessError.invalidConfiguration
                }
                settings.codec = codec
            }
            if let value = environment["DISPLAYCOVE_RECORDING_TEST_FRAME_RATE"] {
                guard let rate = Int(value).flatMap(RecordingFrameRate.init(rawValue:)) else {
                    throw DebugRecordingHarnessError.invalidConfiguration
                }
                settings.frameRate = rate
            }
            if let value = environment["DISPLAYCOVE_RECORDING_TEST_QUALITY"] {
                guard let quality = RecordingQuality(rawValue: value) else {
                    throw DebugRecordingHarnessError.invalidConfiguration
                }
                settings.quality = quality
            }
            for key in ["CURSOR", "MOUSE_CLICKS", "SYSTEM_AUDIO", "MICROPHONE"] {
                if let value = environment["DISPLAYCOVE_RECORDING_TEST_\(key)"],
                   !["0", "1"].contains(value)
                {
                    throw DebugRecordingHarnessError.invalidConfiguration
                }
            }
            settings.showsCursor = environment["DISPLAYCOVE_RECORDING_TEST_CURSOR"] != "0"
            settings.showsMouseClicks = environment["DISPLAYCOVE_RECORDING_TEST_MOUSE_CLICKS"] == "1"
            settings.capturesSystemAudio = environment["DISPLAYCOVE_RECORDING_TEST_SYSTEM_AUDIO"] == "1"
            settings.capturesMicrophone = environment["DISPLAYCOVE_RECORDING_TEST_MICROPHONE"] == "1"
            return settings
        }

        private static func verifyMetadata(
            at outputURL: URL,
            settings: RecordingSettings,
            expectedVideoSize: CGSize
        ) async throws {
            let asset = AVURLAsset(url: outputURL)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoSize = try await videoTracks.first?.load(.naturalSize) ?? .zero
            let videoFrameRate =
                try await videoTracks.first?.load(.nominalFrameRate) ?? 0
            let videoFormats =
                try await videoTracks.first?.load(.formatDescriptions) ?? []
            let videoCodec =
                videoFormats.first.map(CMFormatDescriptionGetMediaSubType) ?? 0
            let expectedCodec = settings.codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
            guard duration.seconds.isFinite, duration.seconds > 0,
                  videoTracks.count == 1, videoSize.width > 0, videoSize.height > 0,
                  videoFrameRate > 0, videoFrameRate <= Float(settings.frameRate.rawValue) + 1,
                  videoCodec == expectedCodec,
                  videoSize == expectedVideoSize
            else {
                throw DebugRecordingHarnessError.invalidOutput
            }

            let metadata =
                "duration=\(duration.seconds), " +
                "videoTracks=\(videoTracks.count), " +
                "audioTracks=\(audioTracks.count), " +
                "size=\(Int(videoSize.width))x\(Int(videoSize.height)), " +
                "frameRate=\(videoFrameRate), codec=\(videoCodec)"
            AppLog.recording.info(
                "Debug recording metadata: \(metadata, privacy: .public)"
            )
        }
    }

    private enum DebugRecordingHarnessError: LocalizedError {
        case missingOutput
        case invalidConfiguration
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .missingOutput: "Recording stopped without producing an output file."
            case .invalidConfiguration: "The recording integration configuration is invalid."
            case .invalidOutput: "The recorded video has invalid duration, tracks, dimensions, frame rate or codec."
            }
        }
    }
#endif
