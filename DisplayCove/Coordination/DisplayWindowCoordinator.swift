import Cocoa

@MainActor
struct ManagedDisplayWindow {
    let identifier: ObjectIdentifier
    let serialNumber: UInt32
    let window: NSWindow
    let viewController: ScreenViewController
}

@MainActor
final class DisplayWindowCoordinator {
    var onStateChanged: (() -> Void)?
    var onError: ((Error, NSWindow?) -> Void)?
    var onRecordingFinished: ((URL) -> Void)?

    private let serialAllocator = DisplaySerialAllocator()
    private let generalPreferences: GeneralPreferences
    private var displayWindows: [ObjectIdentifier: ManagedDisplayWindow] = [:]
    private var activeDisplayWindowIdentifier: ObjectIdentifier?

    init(generalPreferences: GeneralPreferences) {
        self.generalPreferences = generalPreferences
    }

    var activeDisplayWindow: ManagedDisplayWindow? {
        if
            let window = NSApp.keyWindow ?? NSApp.mainWindow,
            let displayWindow = displayWindows[ObjectIdentifier(window)]
        {
            return displayWindow
        }

        guard let activeDisplayWindowIdentifier else {
            return nil
        }
        return displayWindows[activeDisplayWindowIdentifier]
    }

    var allDisplayWindows: [ManagedDisplayWindow] {
        Array(displayWindows.values)
    }

    @discardableResult
    func createScreen() async -> ManagedDisplayWindow? {
        guard let serialNumber = serialAllocator.claim() else {
            onError?(DisplayWindowError.serialNumbersExhausted, nil)
            return nil
        }

        let settings = generalPreferences.settings
        let session = DisplaySession(
            configuration: .standard(serialNumber: serialNumber),
            showsCursor: settings.showsPreviewCursor,
            preservesPhysicalHDR: settings.preservesPhysicalHDR
        )

        let viewController = ScreenViewController(session: session)
        await viewController.applyGeneralSettings(settings)
        let window = makeWindow(
            serialNumber: serialNumber,
            viewController: viewController
        )
        let identifier = ObjectIdentifier(window)

        configureCallbacks(
            identifier: identifier,
            window: window,
            viewController: viewController
        )

        do {
            try await viewController.start()
        } catch {
            await viewController.stop()
            serialAllocator.release(serialNumber)
            onError?(error, nil)
            return nil
        }

        let displayWindow = ManagedDisplayWindow(
            identifier: identifier,
            serialNumber: serialNumber,
            window: window,
            viewController: viewController
        )
        displayWindows[identifier] = displayWindow
        activeDisplayWindowIdentifier = identifier
        window.makeKeyAndOrderFront(nil)

        if viewController.currentResolution != settings.defaultResolution {
            do {
                try await Task.sleep(for: .milliseconds(500))
                try await viewController.setResolution(
                    settings.defaultResolution
                )
            } catch {
                AppLog.display.error(
                    "Could not apply the default resolution: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        onStateChanged?()
        return displayWindow
    }

    func applyGeneralSettings(_ settings: GeneralSettings) async {
        for displayWindow in displayWindows.values {
            await displayWindow.viewController.applyGeneralSettings(settings)

            if displayWindow.viewController.currentResolution !=
                settings.defaultResolution
            {
                do {
                    try await displayWindow.viewController.setResolution(
                        settings.defaultResolution
                    )
                } catch {
                    onError?(error, displayWindow.window)
                }
            }
        }
        onStateChanged?()
    }

    func setResolution(_ resolution: DisplayResolution) async {
        guard let displayWindow = activeDisplayWindow else {
            return
        }

        do {
            try await displayWindow.viewController.setResolution(resolution)
        } catch {
            onError?(error, displayWindow.window)
        }
        onStateChanged?()
    }

    func resumePreview() async {
        guard let displayWindow = activeDisplayWindow else {
            return
        }

        await displayWindow.viewController.resumePreview()
        onStateChanged?()
    }

    func stopAll() async {
        for displayWindow in displayWindows.values {
            if displayWindow.viewController.isRecording {
                do {
                    try await displayWindow.viewController.stopRecording()
                } catch {
                    onError?(error, displayWindow.window)
                }
            }
            await displayWindow.viewController.stop()
        }
    }

    private func makeWindow(
        serialNumber: UInt32,
        viewController: ScreenViewController
    ) -> NSWindow {
        let window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.title = DisplaySessionConfiguration.standard(
            serialNumber: serialNumber
        ).name
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = CGSize(width: 5120, height: 2160)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        return window
    }

    private func configureCallbacks(
        identifier: ObjectIdentifier,
        window: NSWindow,
        viewController: ScreenViewController
    ) {
        viewController.onWindowClosed = { [weak self] in
            self?.removeDisplayWindow(identifier: identifier)
        }
        viewController.onRecordingStateChanged = { [weak self] in
            self?.onStateChanged?()
        }
        viewController.onRecordingError = { [weak self, weak window] error in
            self?.onError?(error, window)
        }
        viewController.onRecordingFinished = { [weak self] url in
            self?.onRecordingFinished?(url)
            self?.onStateChanged?()
        }
        viewController.onPreviewStateChanged = { [weak self] in
            self?.onStateChanged?()
        }
        viewController.onWindowBecameKey = { [weak self] in
            self?.activeDisplayWindowIdentifier = identifier
            self?.onStateChanged?()
        }
        viewController.onResolutionChanged = { [weak self] in
            self?.onStateChanged?()
        }
    }

    private func removeDisplayWindow(identifier: ObjectIdentifier) {
        guard let displayWindow = displayWindows.removeValue(forKey: identifier) else {
            return
        }

        serialAllocator.release(displayWindow.serialNumber)
        if activeDisplayWindowIdentifier == identifier {
            activeDisplayWindowIdentifier = displayWindows.keys.first
        }
        onStateChanged?()
    }
}

private enum DisplayWindowError: LocalizedError {
    case serialNumbersExhausted

    var errorDescription: String? {
        "No virtual display serial numbers are available."
    }
}
