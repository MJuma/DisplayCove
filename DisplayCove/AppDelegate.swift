import Cocoa
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let generalPreferences = GeneralPreferences.shared
    private let recordingPreferences = RecordingPreferences.shared
    private lazy var displayCoordinator = DisplayWindowCoordinator(
        generalPreferences: generalPreferences
    )
    private lazy var recordingCoordinator = RecordingCoordinator(
        preferences: recordingPreferences
    )
    private let menuController = ApplicationMenuController()
    private var settingsWindowController: SettingsWindowController?
    private var isTerminating = false

    func applicationDidFinishLaunching(_: Notification) {
        if terminateIfDuplicateInstance() {
            return
        }

        configureCoordinators()
        menuController.install()

        guard presentFirstLaunchOnboardingIfNeeded() else {
            NSApp.terminate(nil)
            return
        }

        Task {
            do {
                try await ScreenCaptureAuthorization.verify()
            } catch {
                if error is ScreenCaptureAuthorizationError {
                    presentScreenCaptureRestartAlert(error: error)
                } else {
                    presentScreenCapturePermissionAlert(error: error)
                }
                return
            }

            let displayWindow = await displayCoordinator.createScreen()
            #if DEBUG
                if let displayWindow {
                    if DebugLifecycleHarness.isRequested {
                        DebugLifecycleHarness.run(
                            firstDisplay: displayWindow,
                            coordinator: displayCoordinator
                        )
                    } else if
                        ProcessInfo.processInfo.environment[
                            "DISPLAYCOVE_PREVIEW_STOP_TEST"
                        ] == "1"
                    {
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            await displayWindow.viewController
                                .simulateUserStoppedPreview()
                        }
                    } else {
                        DebugRecordingHarness.startIfRequested(
                            for: displayWindow
                        )
                    }
                }
            #endif
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _: NSApplication
    ) -> Bool {
        true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            return .terminateLater
        }
        isTerminating = true

        Task { [self] in
            await displayCoordinator.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureCoordinators() {
        displayCoordinator.onStateChanged = { [weak self] in
            self?.menuController.update()
        }
        displayCoordinator.onError = { [weak self] error, window in
            self?.presentError(error, for: window)
        }
        displayCoordinator.onRecordingFinished = { [weak self] _ in
            self?.menuController.update()
        }

        recordingCoordinator.onError = { [weak self] error, window in
            self?.presentError(error, for: window)
        }
        recordingCoordinator.onStateChanged = { [weak self] in
            self?.menuController.update()
        }

        menuController.activeDisplayProvider = { [weak self] in
            self?.displayCoordinator.activeDisplayWindow
        }
        menuController.onNewScreen = { [weak self] in
            Task {
                let displayWindow = await self?.displayCoordinator.createScreen()
                #if DEBUG
                    if let displayWindow {
                        DebugRecordingHarness.startIfRequested(
                            for: displayWindow
                        )
                    }
                #endif
            }
        }

        menuController.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        menuController.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
        menuController.onResumePreview = { [weak self] in
            Task {
                await self?.displayCoordinator.resumePreview()
            }
        }
        menuController.onStartRecording = { [weak self] in
            guard let self else {
                return
            }
            recordingCoordinator.startRecording(
                for: displayCoordinator.activeDisplayWindow
            )
        }
        menuController.onStopRecording = { [weak self] in
            guard let self else {
                return
            }
            recordingCoordinator.stopRecording(
                for: displayCoordinator.activeDisplayWindow
            )
        }
        menuController.onChangeResolution = { [weak self] resolution in
            Task {
                await self?.displayCoordinator.setResolution(resolution)
            }
        }
    }

    private func terminateIfDuplicateInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let matchingApplications =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
        let matchingProcessIDs = matchingApplications.map(
            \.processIdentifier
        )
        guard ApplicationInstancePolicy.shouldTerminate(
            currentProcessID: currentProcessID,
            matchingProcessIDs: matchingProcessIDs
        ) else {
            return false
        }

        matchingApplications
            .filter { $0.processIdentifier != currentProcessID }
            .min { $0.processIdentifier < $1.processIdentifier }?
            .activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }

    private func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(
            generalPreferences: generalPreferences,
            recordingPreferences: recordingPreferences,
            onGeneralSettingsChanged: { [weak self] settings in
                Task {
                    await self?.displayCoordinator.applyGeneralSettings(settings)
                }
            }
        )
        settingsWindowController = controller
        controller.present()
    }

    private func presentFirstLaunchOnboardingIfNeeded() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let isAutomatedLaunch =
            environment["DISPLAYCOVE_LIFECYCLE_TEST"] == "1" ||
            environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] != nil
        let key = "hasCompletedFirstLaunchOnboarding"
        guard
            !isAutomatedLaunch,
            !UserDefaults.standard.bool(forKey: key)
        else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Welcome to DisplayCove"
        alert.informativeText =
            "DisplayCove creates a separate virtual screen at the resolution you choose. " +
            "Move the windows you want to present onto that screen, then share DisplayCove " +
            "from your meeting or streaming app.\n\n" +
            "macOS will next request Screen & System Audio Recording access so DisplayCove " +
            "can show the virtual screen in its window."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Quit")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    private func presentScreenCapturePermissionAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText =
            "DisplayCove cannot show the virtual display until Screen Recording permission " +
            "is enabled. Grant access in Privacy & Security, then quit and reopen DisplayCove.\n\n" +
            error.localizedDescription
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(
                    string: "x-apple.systempreferences:" +
                        "com.apple.preference.security?Privacy_ScreenCapture"
                )!
            )
        }

        NSApp.terminate(nil)
    }

    private func presentScreenCaptureRestartAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restart DisplayCove"
        alert.informativeText =
            error.localizedDescription +
            "\n\nThe virtual display was not created."
        alert.addButton(withTitle: "Quit DisplayCove")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error, for window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
