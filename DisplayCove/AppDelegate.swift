import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        configureCoordinators()
        menuController.install()

        Task {
            do {
                try await ScreenCaptureAuthorization.verify()
            } catch {
                presentScreenCapturePermissionAlert(error: error)
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

        Task {
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

    private func presentError(_ error: Error, for window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
