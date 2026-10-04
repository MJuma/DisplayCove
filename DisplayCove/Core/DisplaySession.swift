import Cocoa
import IOSurface

enum DisplaySessionError: LocalizedError {
    case displayUnavailable
    case displayDiscoveryTimedOut
    case resolutionUnavailable(DisplayResolution)
    case resolutionChangeTimedOut(DisplayResolution)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "The virtual display is not available."
        case .displayDiscoveryTimedOut:
            "DisplayCove timed out while waiting for the virtual display."
        case let .resolutionUnavailable(resolution):
            "\(resolution.displayName) is not available for this display."
        case let .resolutionChangeTimedOut(resolution):
            "DisplayCove timed out while changing to \(resolution.displayName)."
        }
    }
}

@MainActor
final class DisplaySession {
    var onConfigurationChanged: ((ScreenConfigurationSnapshot) -> Void)?
    var onFrameAvailable: ((IOSurface) -> Void)?
    var onMousePresenceChanged: ((Bool) -> Void)?

    private(set) var screenConfiguration: ScreenConfigurationSnapshot?
    var displayID: CGDirectDisplayID? {
        display?.displayID
    }

    private let configuration: DisplaySessionConfiguration
    private let preservesPhysicalHDR: Bool
    private let backend: VirtualDisplayBackend
    private let captureController = DisplayCaptureController()
    private var showsCursor: Bool
    private var display: VirtualDisplayHandle?
    private var screenObserver: NSObjectProtocol?
    private var mouseTrackingTask: Task<Void, Never>?
    private var isMouseInside = false

    init(
        configuration: DisplaySessionConfiguration = .standard(),
        showsCursor: Bool = true,
        preservesPhysicalHDR: Bool = true,
        backend: VirtualDisplayBackend? = nil
    ) {
        self.configuration = configuration
        self.showsCursor = showsCursor
        self.preservesPhysicalHDR = preservesPhysicalHDR
        self.backend = backend ?? VirtualDisplayBackend()

        captureController.onFrameAvailable = { [weak self] surface in
            self?.onFrameAvailable?(surface)
        }
        captureController.onStopped = { error in
            AppLog.display.error(
                "Preview capture stopped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func start() async throws {
        guard display == nil else {
            return
        }

        let hdrState = preservesPhysicalHDR ? DisplayHDRState.capture() : nil
        let display = try backend.create(configuration: configuration)
        self.display = display
        hdrState?.restoreAfterDisplayChange()

        startScreenObservation()
        startMouseTracking()

        do {
            let screenConfiguration = try await waitForScreenConfiguration()
            applyScreenConfiguration(screenConfiguration)
            try await captureController.start(
                displayID: display.displayID,
                configuration: screenConfiguration,
                showsCursor: showsCursor
            )
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        mouseTrackingTask?.cancel()
        mouseTrackingTask = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        await captureController.stop()
        screenConfiguration = nil
        display = nil

        if isMouseInside {
            isMouseInside = false
            onMousePresenceChanged?(false)
        }
    }

    func moveCursor(to point: CGPoint) {
        guard
            let display,
            point.x.isFinite,
            point.y.isFinite
        else {
            return
        }

        CGDisplayMoveCursorToPoint(display.displayID, point)
    }

    var currentResolution: DisplayResolution? {
        guard let resolution = screenConfiguration?.resolution else {
            return nil
        }

        return DisplayResolution(
            width: Int(resolution.width),
            height: Int(resolution.height)
        )
    }

    var availableResolutions: [DisplayResolution] {
        Array(Set(configuration.modes.map {
            DisplayResolution(width: $0.width, height: $0.height)
        })).sorted {
            if $0.width == $1.width {
                return $0.height > $1.height
            }
            return $0.width > $1.width
        }
    }

    func setResolution(_ resolution: DisplayResolution) async throws {
        guard let display else {
            throw DisplaySessionError.displayUnavailable
        }
        guard availableResolutions.contains(resolution) else {
            throw DisplaySessionError.resolutionUnavailable(resolution)
        }

        try backend.forceResolution(
            resolution,
            configuration: configuration,
            on: display
        )

        do {
            let newConfiguration = try await waitForScreenConfiguration(
                matching: resolution
            )
            applyScreenConfiguration(newConfiguration)
            try await captureController.update(
                configuration: newConfiguration,
                showsCursor: showsCursor
            )
        } catch {
            try? backend.restoreAvailableModes(
                preferredResolution: currentResolution ??
                    configuration.defaultResolution,
                configuration: configuration,
                on: display
            )
            throw error
        }
    }

    func setShowsCursor(_ showsCursor: Bool) async {
        guard showsCursor != self.showsCursor else {
            return
        }

        self.showsCursor = showsCursor
        guard let screenConfiguration else {
            return
        }

        do {
            try await captureController.update(
                configuration: screenConfiguration,
                showsCursor: showsCursor
            )
        } catch {
            AppLog.display.error(
                "Could not update cursor capture: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func startScreenObservation() {
        guard screenObserver == nil else {
            return
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshScreenConfiguration()
            }
        }
    }

    private func refreshScreenConfiguration() async {
        guard
            let display,
            let newConfiguration = ScreenConfigurationResolver.configuration(
                for: display.displayID,
                screens: NSScreen.screens
            ),
            newConfiguration != screenConfiguration
        else {
            return
        }

        applyScreenConfiguration(newConfiguration)
        do {
            try await captureController.update(
                configuration: newConfiguration,
                showsCursor: showsCursor
            )
        } catch {
            AppLog.display.error(
                "Could not update preview capture: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func waitForScreenConfiguration(
        matching resolution: DisplayResolution? = nil
    ) async throws -> ScreenConfigurationSnapshot {
        guard let display else {
            throw DisplaySessionError.displayUnavailable
        }

        for _ in 0 ..< 50 {
            if
                let screenConfiguration =
                ScreenConfigurationResolver.configuration(
                    for: display.displayID,
                    screens: NSScreen.screens
                )
            {
                if let resolution {
                    if
                        Int(screenConfiguration.resolution.width) ==
                        resolution.width,
                        Int(screenConfiguration.resolution.height) ==
                        resolution.height
                    {
                        return screenConfiguration
                    }
                } else {
                    return screenConfiguration
                }
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        if let resolution {
            throw DisplaySessionError.resolutionChangeTimedOut(resolution)
        }
        throw DisplaySessionError.displayDiscoveryTimedOut
    }

    private func applyScreenConfiguration(
        _ screenConfiguration: ScreenConfigurationSnapshot
    ) {
        guard screenConfiguration != self.screenConfiguration else {
            return
        }

        self.screenConfiguration = screenConfiguration
        onConfigurationChanged?(screenConfiguration)
    }

    private func startMouseTracking() {
        guard mouseTrackingTask == nil else {
            return
        }

        mouseTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateMousePresence()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func updateMousePresence() {
        guard let display else {
            updateMousePresence(false)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screenContainingMouse = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }
        updateMousePresence(screenContainingMouse?.displayID == display.displayID)
    }

    private func updateMousePresence(_ isMouseInside: Bool) {
        guard isMouseInside != self.isMouseInside else {
            return
        }

        self.isMouseInside = isMouseInside
        onMousePresenceChanged?(isMouseInside)
    }
}
