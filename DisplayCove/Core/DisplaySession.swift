import Cocoa
import IOSurface
import ScreenCaptureKit

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
    var onPreviewStateChanged: ((DisplayPreviewState) -> Void)?

    private(set) var screenConfiguration: ScreenConfigurationSnapshot?
    private(set) var previewState: DisplayPreviewState = .stopped {
        didSet {
            guard previewState != oldValue else {
                return
            }
            onPreviewStateChanged?(previewState)
        }
    }

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
    private var previewRecoveryTask: Task<Void, Never>?
    private var previewWatchdogTask: Task<Void, Never>?
    private var lastPreviewFrameDate: Date?
    private var isMouseInside = false
    private var isStopping = true

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
            guard let self else {
                return
            }
            lastPreviewFrameDate = Date()
            previewState = .running
            onFrameAvailable?(surface)
        }
        captureController.onStopped = { [weak self] error in
            guard let self else {
                return
            }
            let error = error as NSError
            AppLog.display.error(
                "Preview capture stopped [\(error.domain, privacy: .public) \(error.code)]: \(error.localizedDescription, privacy: .public)"
            )
            handlePreviewStopped(error)
        }
    }

    func start() async throws {
        guard display == nil else {
            return
        }
        isStopping = false

        let hdrState = preservesPhysicalHDR ? DisplayHDRState.capture() : nil
        let display = try backend.create(configuration: configuration)
        self.display = display
        hdrState?.restoreAfterDisplayChange()

        startScreenObservation()
        startMouseTracking()

        let screenConfiguration: ScreenConfigurationSnapshot
        do {
            screenConfiguration = try await waitForScreenConfiguration()
        } catch {
            await stop()
            throw error
        }

        applyScreenConfiguration(screenConfiguration)
        do {
            try await startPreviewCapture(
                configuration: screenConfiguration,
                state: .starting
            )
        } catch {
            handlePreviewStartFailure(error)
        }
    }

    func stop() async {
        isStopping = true
        previewRecoveryTask?.cancel()
        previewRecoveryTask = nil
        previewWatchdogTask?.cancel()
        previewWatchdogTask = nil
        lastPreviewFrameDate = nil

        mouseTrackingTask?.cancel()
        mouseTrackingTask = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        await captureController.stop()
        if let display {
            try? backend.restoreAvailableModes(
                preferredResolution: currentResolution ??
                    configuration.defaultResolution,
                configuration: configuration,
                on: display
            )
            try? await Task.sleep(for: .milliseconds(100))
        }
        previewState = .stopped
        screenConfiguration = nil
        display = nil

        if isMouseInside {
            isMouseInside = false
            onMousePresenceChanged?(false)
        }
    }

    func resumePreview() async {
        guard let screenConfiguration, let display else {
            previewState = .failed(
                DisplaySessionError.displayUnavailable.localizedDescription
            )
            return
        }

        isStopping = false
        previewRecoveryTask?.cancel()
        previewRecoveryTask = nil

        do {
            previewState = .starting
            lastPreviewFrameDate = Date()
            try await captureController.startUsingPicker(
                displayID: display.displayID,
                configuration: screenConfiguration,
                showsCursor: showsCursor
            )
            startPreviewWatchdog()
        } catch is DisplayCapturePickerError {
            previewState = .pausedByUser
        } catch {
            handlePreviewStartFailure(error)
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

    #if DEBUG
        func simulateUserStoppedPreview() async {
            await captureController.stop()
            handlePreviewStopped(
                NSError(
                    domain: SCStreamErrorDomain,
                    code: SCStreamError.Code.userStopped.rawValue
                )
            )
        }

        func resumePreviewForTesting() async {
            guard let screenConfiguration else {
                return
            }

            isStopping = false
            do {
                try await startPreviewCapture(
                    configuration: screenConfiguration,
                    state: .starting
                )
            } catch {
                handlePreviewStartFailure(error)
            }
        }
    #endif

    private func startPreviewCapture(
        configuration: ScreenConfigurationSnapshot,
        state: DisplayPreviewState
    ) async throws {
        guard let display else {
            throw DisplaySessionError.displayUnavailable
        }

        previewState = state
        lastPreviewFrameDate = Date()
        try await captureController.start(
            displayID: display.displayID,
            configuration: configuration,
            showsCursor: showsCursor
        )
        startPreviewWatchdog()
    }

    private func handlePreviewStopped(_ error: Error) {
        guard !isStopping else {
            return
        }

        previewWatchdogTask?.cancel()
        previewWatchdogTask = nil
        lastPreviewFrameDate = nil

        switch DisplayPreviewRecovery.stopReason(for: error) {
        case .userStopped:
            previewRecoveryTask?.cancel()
            previewRecoveryTask = nil
            previewState = .pausedByUser
        case .permissionRequired:
            previewRecoveryTask?.cancel()
            previewRecoveryTask = nil
            previewState = .permissionRequired
        case .recoverable:
            scheduleAutomaticPreviewRecovery(after: error)
        case .failed:
            previewRecoveryTask?.cancel()
            previewRecoveryTask = nil
            previewState = .failed(error.localizedDescription)
        }
    }

    private func handlePreviewStartFailure(_ error: Error) {
        switch DisplayPreviewRecovery.stopReason(for: error) {
        case .userStopped:
            previewState = .pausedByUser
        case .permissionRequired:
            previewState = .permissionRequired
        case .recoverable:
            scheduleAutomaticPreviewRecovery(after: error)
        case .failed:
            previewState = .failed(error.localizedDescription)
        }
    }

    private func scheduleAutomaticPreviewRecovery(after initialError: Error) {
        guard previewRecoveryTask == nil else {
            return
        }

        previewRecoveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                previewRecoveryTask = nil
            }

            var latestError = initialError
            for attempt in 1 ... DisplayPreviewRecovery.maxAutomaticRetryAttempts {
                previewState = .reconnecting(attempt: attempt)
                do {
                    try await Task.sleep(
                        for: DisplayPreviewRecovery.retryDelay(for: attempt)
                    )
                } catch {
                    return
                }

                guard
                    !Task.isCancelled,
                    let screenConfiguration,
                    display != nil
                else {
                    return
                }

                do {
                    try await startPreviewCapture(
                        configuration: screenConfiguration,
                        state: .reconnecting(attempt: attempt)
                    )
                    return
                } catch {
                    latestError = error
                    let reason = DisplayPreviewRecovery.stopReason(for: error)
                    guard reason == .recoverable else {
                        handlePreviewStartFailure(error)
                        return
                    }
                }
            }

            previewState = .failed(latestError.localizedDescription)
        }
    }

    private func startPreviewWatchdog() {
        previewWatchdogTask?.cancel()
        previewWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }

                guard
                    let self,
                    previewState.expectsFrames,
                    let lastPreviewFrameDate,
                    Date().timeIntervalSince(lastPreviewFrameDate) >= 8
                else {
                    continue
                }

                let error = DisplayPreviewWatchdogError()
                AppLog.display.error(
                    "\(error.localizedDescription, privacy: .public)"
                )
                await captureController.stop()
                previewWatchdogTask = nil
                scheduleAutomaticPreviewRecovery(after: error)
                return
            }
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

    private struct DisplayPreviewWatchdogError: LocalizedError {
        var errorDescription: String? {
            "The preview stopped receiving frames."
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
