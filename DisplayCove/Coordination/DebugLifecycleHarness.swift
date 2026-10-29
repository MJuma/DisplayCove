#if DEBUG
    import Cocoa
    import Darwin

    @MainActor
    enum DebugIntegrationEnvironment {
        static var isRequested: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["DISPLAYCOVE_LIFECYCLE_TEST"] == "1" ||
                environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] != nil
        }

        private(set) static var directory: URL?
        static var failure: (any Error)?

        static func prepare() throws {
            let environment = ProcessInfo.processInfo.environment
            let lifecycle = environment["DISPLAYCOVE_LIFECYCLE_TEST"] == "1"
            let recording = environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] != nil
            let expected = recording ? "dev.juma.DisplayCove.recording-integration" :
                "dev.juma.DisplayCove.lifecycle-integration"
            guard lifecycle != recording,
                  !recording || environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] == "1",
                  Bundle.main.bundleIdentifier == expected,
                  let id = environment["DISPLAYCOVE_INTEGRATION_RUN_ID"],
                  UUID(uuidString: id) != nil
            else {
                throw IntegrationEnvironmentError(message: "Use the isolated integration script, not a production app bundle.")
            }
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("displaycove-integration-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            directory = root
            print("DISPLAYCOVE_INTEGRATION_DIRECTORY=\(root.path)")
            fflush(stdout)
        }

        static func recordFailure(_ error: any Error) {
            failure = error
            AppLog.lifecycle.error("Integration failure: \(error.localizedDescription, privacy: .public)")
        }

        static func recordingURL() throws -> URL {
            guard let directory else {
                throw IntegrationEnvironmentError(message: "The isolated test directory was not prepared.")
            }
            return directory.appendingPathComponent("recording.mov")
        }

        static func finish(error: (any Error)?, recording: Bool = false) -> Never {
            var failure = error ?? failure
            if let directory,
               ProcessInfo.processInfo.environment["DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT"] != "1"
            {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    failure = error
                }
            }
            let prefix = recording ? "DISPLAYCOVE_RECORDING_INTEGRATION" : "DISPLAYCOVE_LIFECYCLE_INTEGRATION"
            if let failure {
                print("\(prefix)_FAILURE: \(failure.localizedDescription)")
            } else {
                print("\(prefix)_SUCCESS")
            }
            fflush(stdout)
            _exit(failure == nil ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private struct IntegrationEnvironmentError: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    @MainActor
    enum DebugLifecycleHarness {
        static var isRequested: Bool {
            ProcessInfo.processInfo.environment["DISPLAYCOVE_LIFECYCLE_TEST"] == "1"
        }

        static func run(
            firstDisplay: ManagedDisplayWindow,
            coordinator: DisplayWindowCoordinator
        ) {
            guard isRequested else {
                return
            }

            Task {
                var failure: (any Error)?
                do {
                    try await waitUntil {
                        firstDisplay.viewController.hasReceivedPreviewFrame
                    }
                    guard let firstDisplayID = firstDisplay.viewController.displayID else {
                        throw HarnessError.missingDisplayID
                    }

                    guard let secondDisplay = await coordinator.createScreen() else {
                        throw HarnessError.secondDisplayCreationFailed
                    }
                    try await waitUntil {
                        secondDisplay.viewController.hasReceivedPreviewFrame
                    }
                    guard let secondDisplayID = secondDisplay.viewController.displayID else {
                        throw HarnessError.missingDisplayID
                    }

                    await coordinator.setResolution(
                        DisplayResolution(width: 1280, height: 720)
                    )
                    try await waitUntil {
                        secondDisplay.viewController.currentResolution ==
                            DisplayResolution(width: 1280, height: 720) &&
                            secondDisplay.viewController.displayScaleFactor == 2
                    }
                    try await Task.sleep(for: .seconds(1))
                    guard
                        secondDisplay.viewController.currentResolution ==
                        DisplayResolution(width: 1280, height: 720)
                    else {
                        throw HarnessError.resolutionDidNotPersist
                    }

                    await secondDisplay.viewController.simulateUserStoppedPreview()
                    try await waitUntil {
                        secondDisplay.viewController.previewState == .pausedByUser
                    }
                    await secondDisplay.viewController.resumePreviewForTesting()
                    try await waitUntil {
                        secondDisplay.viewController.previewState == .running
                    }

                    secondDisplay.window.performClose(nil)
                    try await waitUntil {
                        guard coordinator.allDisplayWindows.count == 1 else {
                            return false
                        }
                        return try !isDisplayOnline(secondDisplayID)
                    }

                    guard try isDisplayOnline(firstDisplayID) else {
                        throw HarnessError.firstDisplayUnexpectedlyRemoved
                    }

                    await coordinator.stopAll()
                    try await waitUntil {
                        try !isDisplayOnline(firstDisplayID)
                    }
                } catch {
                    failure = error
                }
                await coordinator.stopAll()
                DebugIntegrationEnvironment.finish(error: failure)
            }
        }

        private static func waitUntil(
            timeout: Duration = .seconds(8),
            condition: @escaping @MainActor () throws -> Bool
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout

            while try !condition() {
                if let failure = DebugIntegrationEnvironment.failure {
                    throw failure
                }
                guard clock.now < deadline else {
                    throw HarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        private static func isDisplayOnline(
            _ displayID: CGDirectDisplayID
        ) throws -> Bool {
            var displayCount: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
                throw HarnessError.displayQueryFailed
            }
            var displayIDs = [CGDirectDisplayID](repeating: 0, count: max(1, Int(displayCount)))
            guard CGGetOnlineDisplayList(
                UInt32(displayIDs.count),
                &displayIDs,
                &displayCount
            ) == .success else {
                throw HarnessError.displayQueryFailed
            }

            return displayIDs.prefix(Int(displayCount)).contains(displayID)
        }
    }

    private enum HarnessError: LocalizedError {
        case timedOut
        case missingDisplayID
        case secondDisplayCreationFailed
        case firstDisplayUnexpectedlyRemoved
        case resolutionDidNotPersist
        case displayQueryFailed

        var errorDescription: String? {
            switch self {
            case .timedOut:
                "The integration test timed out."
            case .missingDisplayID:
                "A display ID was unavailable."
            case .secondDisplayCreationFailed:
                "The second virtual display could not be created."
            case .firstDisplayUnexpectedlyRemoved:
                "Closing the second display removed the first display."
            case .resolutionDidNotPersist:
                "The selected resolution reverted after it was applied."
            case .displayQueryFailed:
                "The online display list could not be read; teardown cannot be verified."
            }
        }
    }
#endif
