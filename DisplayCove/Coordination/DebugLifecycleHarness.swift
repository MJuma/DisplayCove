#if DEBUG
    import Cocoa
    import Darwin

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
                        coordinator.allDisplayWindows.count == 1 &&
                            !isDisplayOnline(secondDisplayID)
                    }

                    guard isDisplayOnline(firstDisplayID) else {
                        throw HarnessError.firstDisplayUnexpectedlyRemoved
                    }

                    await coordinator.stopAll()
                    try await waitUntil {
                        !isDisplayOnline(firstDisplayID)
                    }
                    print("DISPLAYCOVE_LIFECYCLE_INTEGRATION_SUCCESS")
                    fflush(stdout)
                } catch {
                    print(
                        "DISPLAYCOVE_LIFECYCLE_INTEGRATION_FAILURE: " +
                            error.localizedDescription
                    )
                    fflush(stdout)
                }

                _exit(0)
            }
        }

        private static func waitUntil(
            timeout: Duration = .seconds(8),
            condition: @escaping @MainActor () -> Bool
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout

            while !condition() {
                guard clock.now < deadline else {
                    throw HarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        private static func isDisplayOnline(
            _ displayID: CGDirectDisplayID
        ) -> Bool {
            var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
            var displayCount: UInt32 = 0
            guard CGGetOnlineDisplayList(
                UInt32(displayIDs.count),
                &displayIDs,
                &displayCount
            ) == .success else {
                return false
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
            }
        }
    }
#endif
