import Cocoa
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var instanceLock: ApplicationInstanceLock?
    private lazy var generalPreferences: GeneralPreferences = {
        #if DEBUG
            if DebugIntegrationEnvironment.isRequested {
                return GeneralPreferences(persistsChanges: false)
            }
        #endif
        return .shared
    }()

    private lazy var recordingPreferences: RecordingPreferences = {
        #if DEBUG
            if DebugIntegrationEnvironment.isRequested {
                return RecordingPreferences(persistsChanges: false)
            }
        #endif
        return .shared
    }()

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
        guard claimPrimaryInstance() else {
            return
        }
        #if DEBUG
            if DebugIntegrationEnvironment.isRequested {
                do {
                    try DebugIntegrationEnvironment.prepare()
                } catch {
                    DebugIntegrationEnvironment.finish(error: error)
                }
            }
        #endif

        configureCoordinators()
        menuController.install()

        guard presentFirstLaunchOnboardingIfNeeded() else {
            NSApp.terminate(nil)
            return
        }
        presentPreferencesIssueIfNeeded()

        Task {
            do {
                try await ScreenCaptureAuthorization.verify()
            } catch {
                #if DEBUG
                    if DebugIntegrationEnvironment.isRequested {
                        await displayCoordinator.stopAll()
                        DebugIntegrationEnvironment.finish(error: error)
                    }
                #endif
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
                    } else {
                        DebugRecordingHarness.startIfRequested(
                            for: displayWindow, coordinator: displayCoordinator
                        )
                    }
                } else if DebugIntegrationEnvironment.isRequested {
                    await displayCoordinator.stopAll()
                    DebugIntegrationEnvironment.finish(error: DebugIntegrationEnvironment.failure ??
                        NSError(domain: "DisplayCoveIntegration", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "The first virtual display could not be created.",
                        ]))
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
        guard instanceLock != nil else {
            return .terminateNow
        }
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
            #if DEBUG
                if DebugIntegrationEnvironment.isRequested {
                    DebugIntegrationEnvironment.recordFailure(error)
                    return
                }
            #endif
            self?.presentError(error, for: window)
        }
        displayCoordinator.onRecordingFinished = { [weak self] _ in
            self?.menuController.update()
        }

        recordingCoordinator.onError = { [weak self] error, window in
            #if DEBUG
                if DebugIntegrationEnvironment.isRequested {
                    DebugIntegrationEnvironment.recordFailure(error)
                    return
                }
            #endif
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
                guard let self else { return }
                let displayWindow = await self.displayCoordinator.createScreen()
                #if DEBUG
                    if let displayWindow {
                        DebugRecordingHarness.startIfRequested(
                            for: displayWindow, coordinator: self.displayCoordinator
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

    private func claimPrimaryInstance() -> Bool {
        do {
            if let lock = try ApplicationInstanceLock.claimApplication() {
                instanceLock = lock
                return true
            }
            AppLog.lifecycle.notice("Another DisplayCove instance owns the application lock")
            if let identifier = Bundle.main.bundleIdentifier {
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                    .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                    .activate(options: [.activateAllWindows])
            }
        } catch {
            AppLog.lifecycle.error("Instance ownership failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "DisplayCove could not start"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
        }
        NSApp.terminate(nil)
        return false
    }

    private func presentPreferencesIssueIfNeeded() {
        guard generalPreferences.persistenceError != nil || recordingPreferences.persistenceError != nil else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some saved settings could not be loaded"
        alert.informativeText = "The original data is preserved. Default settings will be used for this session. " +
            "Open Settings to review the error and explicitly reset saved settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Continue")
        if alert.runModal() == .alertFirstButtonReturn {
            showSettings()
        }
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
        #if DEBUG
            let isAutomatedLaunch = DebugIntegrationEnvironment.isRequested
        #else
            let isAutomatedLaunch = false
        #endif
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
            "macOS denied Screen Recording access to this copy of DisplayCove. " +
            "If DisplayCove is already enabled in Privacy & Security, macOS may have saved " +
            "permission for an older or differently signed copy. Copy the reset command, " +
            "run it in Terminal, then reopen DisplayCove and grant access again.\n\n" +
            error.localizedDescription
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Copy Reset Command")
        alert.addButton(withTitle: "Quit DisplayCove")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(
                    string: "x-apple.systempreferences:" +
                        "com.apple.preference.security?Privacy_ScreenCapture"
                )!
            )
        } else if response == .alertSecondButtonReturn {
            let command =
                "tccutil reset ScreenCapture dev.juma.DisplayCove"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)

            let confirmation = NSAlert()
            confirmation.alertStyle = .informational
            confirmation.messageText = "Reset Command Copied"
            confirmation.informativeText =
                "Quit DisplayCove, paste the command into Terminal, then reopen " +
                "DisplayCove and grant Screen Recording access."
            confirmation.addButton(withTitle: "Quit DisplayCove")
            confirmation.runModal()
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
