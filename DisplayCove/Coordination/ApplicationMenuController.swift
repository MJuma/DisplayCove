import Cocoa

@MainActor
final class ApplicationMenuController: NSObject, NSMenuDelegate {
    var onNewScreen: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onResumePreview: (() -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onChangeResolution: ((DisplayResolution) -> Void)?
    var activeDisplayProvider: (() -> ManagedDisplayWindow?)?

    private let recordingMenu = NSMenu(title: "Recording")
    private let resolutionMenu = NSMenu(title: "Resolution")
    private let startRecordingMenuItem = NSMenuItem(
        title: "Start Recording…",
        action: #selector(startRecording),
        keyEquivalent: "r"
    )
    private let stopRecordingMenuItem = NSMenuItem(
        title: "Stop Recording",
        action: #selector(stopRecording),
        keyEquivalent: ""
    )
    private let resumePreviewMenuItem = NSMenuItem(
        title: "Resume Preview",
        action: #selector(resumePreview),
        keyEquivalent: "r"
    )

    func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeApplicationMenu())
        mainMenu.addItem(makeRecordingMenu())
        mainMenu.addItem(makeResolutionMenu())
        NSApplication.shared.mainMenu = mainMenu
        update()
    }

    func update() {
        updatePreviewMenu()
        updateRecordingMenu()
        updateResolutionMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recordingMenu {
            updateRecordingMenu()
        } else if menu === resolutionMenu {
            updateResolutionMenu()
        }
    }

    private func makeApplicationMenu() -> NSMenuItem {
        let rootItem = NSMenuItem()
        let menu = NSMenu(title: "DisplayCove")

        let newScreenItem = NSMenuItem(
            title: "New Screen",
            action: #selector(newScreen),
            keyEquivalent: "n"
        )
        newScreenItem.target = self
        resumePreviewMenuItem.keyEquivalentModifierMask = [.command, .option]
        resumePreviewMenuItem.target = self

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit DisplayCove",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )

        menu.addItem(newScreenItem)
        menu.addItem(resumePreviewMenuItem)
        menu.addItem(.separator())
        menu.addItem(checkForUpdatesItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        rootItem.submenu = menu
        return rootItem
    }

    private func makeRecordingMenu() -> NSMenuItem {
        let rootItem = NSMenuItem()
        startRecordingMenuItem.keyEquivalentModifierMask = [.command, .shift]
        startRecordingMenuItem.target = self
        stopRecordingMenuItem.target = self
        recordingMenu.addItem(startRecordingMenuItem)
        recordingMenu.addItem(stopRecordingMenuItem)
        recordingMenu.autoenablesItems = false
        recordingMenu.delegate = self
        rootItem.submenu = recordingMenu
        return rootItem
    }

    private func makeResolutionMenu() -> NSMenuItem {
        let rootItem = NSMenuItem()
        resolutionMenu.autoenablesItems = false
        resolutionMenu.delegate = self
        rootItem.submenu = resolutionMenu
        return rootItem
    }

    private func updateRecordingMenu() {
        let viewController = activeDisplayProvider?()?.viewController
        startRecordingMenuItem.isEnabled =
            viewController != nil && viewController?.isRecording == false
        stopRecordingMenuItem.isEnabled = viewController?.isRecording == true
    }

    private func updatePreviewMenu() {
        resumePreviewMenuItem.isEnabled =
            activeDisplayProvider?()?.viewController.canResumePreview == true
    }

    private func updateResolutionMenu() {
        resolutionMenu.removeAllItems()

        guard let viewController = activeDisplayProvider?()?.viewController else {
            let item = NSMenuItem(
                title: "No Active Screen",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            resolutionMenu.addItem(item)
            return
        }

        let currentResolution = viewController.currentResolution
        for resolution in viewController.availableResolutions {
            let item = NSMenuItem(
                title: resolution.displayName,
                action: #selector(changeResolution),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = resolution
            item.state = resolution == currentResolution ? .on : .off
            item.isEnabled = !viewController.isRecording
            resolutionMenu.addItem(item)
        }
    }

    @objc private func newScreen() {
        onNewScreen?()
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func resumePreview() {
        onResumePreview?()
    }

    @objc private func startRecording() {
        onStartRecording?()
    }

    @objc private func stopRecording() {
        onStopRecording?()
    }

    @objc private func changeResolution(_ menuItem: NSMenuItem) {
        guard let resolution = menuItem.representedObject as? DisplayResolution else {
            return
        }
        onChangeResolution?(resolution)
    }
}
