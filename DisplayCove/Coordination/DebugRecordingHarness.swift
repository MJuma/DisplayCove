#if DEBUG
    import AVFoundation
    import Cocoa
    import Darwin

    @MainActor
    enum DebugRecordingHarness {
        static func startIfRequested(for displayWindow: ManagedDisplayWindow) {
            let environment = ProcessInfo.processInfo.environment
            guard let outputPath = environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] else {
                return
            }

            var settings = RecordingSettings()
            if let codec = environment["DISPLAYCOVE_RECORDING_TEST_CODEC"] {
                settings.codec = RecordingCodec(rawValue: codec) ?? settings.codec
            }
            if
                let frameRate = environment["DISPLAYCOVE_RECORDING_TEST_FRAME_RATE"]
                .flatMap(Int.init)
            {
                settings.frameRate =
                    RecordingFrameRate(rawValue: frameRate) ?? settings.frameRate
            }
            if let quality = environment["DISPLAYCOVE_RECORDING_TEST_QUALITY"] {
                settings.quality =
                    RecordingQuality(rawValue: quality) ?? settings.quality
            }
            if let showsCursor = environment["DISPLAYCOVE_RECORDING_TEST_CURSOR"] {
                settings.showsCursor = showsCursor != "0"
            }
            settings.showsMouseClicks =
                environment["DISPLAYCOVE_RECORDING_TEST_MOUSE_CLICKS"] == "1"
            settings.capturesSystemAudio =
                environment["DISPLAYCOVE_RECORDING_TEST_SYSTEM_AUDIO"] == "1"
            settings.capturesMicrophone =
                environment["DISPLAYCOVE_RECORDING_TEST_MICROPHONE"] == "1"
            let duration = Double(
                environment["DISPLAYCOVE_RECORDING_TEST_DURATION"] ?? ""
            ) ?? 2

            Task {
                do {
                    try await Task.sleep(for: .seconds(1))
                    try await displayWindow.viewController.startRecording(
                        to: URL(fileURLWithPath: outputPath),
                        settings: settings
                    )
                    try await Task.sleep(for: .seconds(max(0.1, duration)))
                    let outputURL =
                        try await displayWindow.viewController.stopRecording()
                    AppLog.recording.info(
                        "Debug recording completed: \((outputURL?.path ?? outputPath), privacy: .public)"
                    )
                    if let outputURL {
                        try await logMetadata(at: outputURL)
                        if environment["DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT"] != "1" {
                            try FileManager.default.removeItem(at: outputURL)
                        }
                    }
                    await displayWindow.viewController.stop()
                    print("DISPLAYCOVE_RECORDING_INTEGRATION_SUCCESS")
                    fflush(stdout)
                } catch {
                    AppLog.recording.error(
                        "Debug recording failed: \(error.localizedDescription, privacy: .public)"
                    )
                    await displayWindow.viewController.stop()
                    print(
                        "DISPLAYCOVE_RECORDING_INTEGRATION_FAILURE: " +
                            error.localizedDescription
                    )
                    fflush(stdout)
                }

                _exit(0)
            }
        }

        private static func logMetadata(at outputURL: URL) async throws {
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
#endif
