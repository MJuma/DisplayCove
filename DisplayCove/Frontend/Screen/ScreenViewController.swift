import Cocoa

class ScreenViewController: NSViewController, NSWindowDelegate {
    var onWindowClosed: (() -> Void)?
    var onRecordingStateChanged: (() -> Void)?
    var onRecordingError: ((Error) -> Void)?
    var onRecordingFinished: ((URL) -> Void)?
    var onWindowBecameKey: (() -> Void)?
    var onResolutionChanged: (() -> Void)?
    var onPreviewStateChanged: (() -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickOnScreen)))

        configureResumePreviewButton()

        recordingIndicator.translatesAutoresizingMaskIntoConstraints = false
        recordingIndicator.isHidden = true
        view.addSubview(recordingIndicator)
        NSLayoutConstraint.activate([
            recordingIndicator.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            recordingIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private let session: DisplaySession
    private let recordingIndicator = RecordingIndicatorView()
    private let resumePreviewPanel = NSVisualEffectView()
    private lazy var resumePreviewButton = NSButton(
        title: "Resume Preview",
        target: self,
        action: #selector(resumePreviewAction)
    )
    private var isWindowHighlighted = false
    private var previousResolution: CGSize?
    private(set) var hasReceivedPreviewFrame = false
    private var isClosingAfterRecording = false
    private var bringsWindowToFront = true

    private lazy var recordingController: DisplayRecordingController = {
        let controller = DisplayRecordingController()
        controller.onStateChanged = { [weak self] state in
            self?.recordingIndicator.isHidden = state == .idle
            self?.onRecordingStateChanged?()
        }
        controller.onDurationChanged = { [weak self] duration in
            self?.recordingIndicator.update(duration: duration)
        }
        controller.onFinished = { [weak self] url in
            self?.recordingIndicator.update(duration: 0)
            self?.onRecordingFinished?(url)
        }
        controller.onFailure = { [weak self] error in
            self?.recordingIndicator.update(duration: 0)
            self?.onRecordingError?(error)
        }
        return controller
    }()

    init(session: DisplaySession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        session.onConfigurationChanged = { [weak self] configuration in
            self?.updateScreenConfiguration(configuration)
        }
        session.onFrameAvailable = { [weak self] frameSurface in
            self?.hasReceivedPreviewFrame = true
            self?.view.layer?.contents = frameSurface
        }
        session.onMousePresenceChanged = { [weak self] isMouseInside in
            self?.updateWindowHighlight(isMouseInside)
        }
        session.onPreviewStateChanged = { [weak self] state in
            self?.updatePreviewState(state)
        }
        updatePreviewState(session.previewState)
    }

    func start() async throws {
        try await session.start()
    }

    func stop() async {
        await session.stop()
        previousResolution = nil
        view.layer?.contents = nil
    }

    var availableResolutions: [DisplayResolution] {
        session.availableResolutions
    }

    var currentResolution: DisplayResolution? {
        session.currentResolution
    }

    var displayID: CGDirectDisplayID? {
        session.displayID
    }

    var displayScaleFactor: CGFloat? {
        session.screenConfiguration?.scaleFactor
    }

    var previewState: DisplayPreviewState {
        session.previewState
    }

    var canResumePreview: Bool {
        switch previewState {
        case .failed, .pausedByUser, .permissionRequired:
            true
        case .reconnecting:
            true
        case .running, .starting, .stopped:
            false
        }
    }

    func setResolution(_ resolution: DisplayResolution) async throws {
        try await session.setResolution(resolution)
    }

    func resumePreview() async {
        await session.resumePreview()
    }

    func applyGeneralSettings(_ settings: GeneralSettings) async {
        bringsWindowToFront = settings.bringsWindowToFront
        await session.setShowsCursor(settings.showsPreviewCursor)
    }

    var isRecording: Bool {
        recordingController.isActive
    }

    func startRecording(
        to outputURL: URL,
        settings: RecordingSettings
    ) async throws {
        guard
            let displayID = session.displayID,
            let screenConfiguration = session.screenConfiguration
        else {
            throw DisplayRecordingError.displayUnavailable
        }

        recordingIndicator.update(duration: 0)
        try await recordingController.start(
            displayID: displayID,
            screenConfiguration: screenConfiguration,
            outputURL: outputURL,
            settings: settings
        )
    }

    @discardableResult
    func stopRecording() async throws -> URL? {
        guard recordingController.isActive else {
            return nil
        }

        return try await recordingController.stop()
    }

    #if DEBUG
        func simulateUserStoppedPreview() async {
            await session.simulateUserStoppedPreview()
        }

        func resumePreviewForTesting() async {
            await session.resumePreviewForTesting()
        }
    #endif

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        guard
            let screenResolution = previousResolution,
            let snappedContentSize = WindowResizeGeometry.snappedContentSize(
                proposedContentSize: window.contentRect(
                    forFrameRect: NSRect(origin: .zero, size: frameSize)
                ).size,
                nativeResolution: screenResolution,
                snappingThreshold: 30
            )
        else {
            return frameSize
        }

        return window.frameRect(
            forContentRect: NSRect(origin: .zero, size: snappedContentSize)
        ).size
    }

    func windowWillClose(_: Notification) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await session.stop()
            onWindowClosed?()
            onWindowClosed = nil
        }
    }

    func windowDidBecomeKey(_: Notification) {
        onWindowBecameKey?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isRecording, !isClosingAfterRecording else {
            return true
        }

        isClosingAfterRecording = true
        Task { [weak self, weak sender] in
            defer {
                self?.isClosingAfterRecording = false
                sender?.performClose(nil)
            }

            do {
                try await self?.stopRecording()
            } catch {
                self?.onRecordingError?(error)
            }
        }
        return false
    }

    @objc private func didClickOnScreen(_ gestureRecognizer: NSGestureRecognizer) {
        guard
            let screenResolution = previousResolution,
            let onScreenPoint = DisplayGeometry.displayPoint(
                from: gestureRecognizer.location(in: view),
                viewSize: view.frame.size,
                displayResolution: screenResolution
            )
        else {
            return
        }

        session.moveCursor(to: onScreenPoint)
    }

    @objc private func resumePreviewAction() {
        Task {
            await session.resumePreview()
        }
    }

    private func configureResumePreviewButton() {
        resumePreviewPanel.translatesAutoresizingMaskIntoConstraints = false
        resumePreviewPanel.blendingMode = .withinWindow
        resumePreviewPanel.material = .hudWindow
        resumePreviewPanel.state = .active
        resumePreviewPanel.wantsLayer = true
        resumePreviewPanel.layer?.cornerRadius = 16
        resumePreviewPanel.layer?.borderWidth = 2
        resumePreviewPanel.layer?.borderColor =
            (NSColor(named: "AccentColor") ?? .controlAccentColor)
                .withAlphaComponent(0.9)
                .cgColor
        resumePreviewPanel.layer?.shadowColor = NSColor.black.cgColor
        resumePreviewPanel.layer?.shadowOpacity = 0.55
        resumePreviewPanel.layer?.shadowRadius = 18
        resumePreviewPanel.layer?.shadowOffset = CGSize(width: 0, height: -6)
        resumePreviewPanel.isHidden = true

        resumePreviewButton.translatesAutoresizingMaskIntoConstraints = false
        resumePreviewButton.bezelStyle = .rounded
        resumePreviewButton.bezelColor =
            NSColor(named: "AccentColor") ?? .controlAccentColor
        resumePreviewButton.contentTintColor = .white
        resumePreviewButton.controlSize = .large
        resumePreviewButton.font = .systemFont(ofSize: 17, weight: .semibold)
        resumePreviewButton.setAccessibilityLabel("Resume DisplayCove Preview")

        resumePreviewPanel.addSubview(resumePreviewButton)
        view.addSubview(resumePreviewPanel)
        NSLayoutConstraint.activate([
            resumePreviewPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resumePreviewPanel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            resumePreviewPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            resumePreviewButton.leadingAnchor.constraint(
                equalTo: resumePreviewPanel.leadingAnchor,
                constant: 24
            ),
            resumePreviewButton.trailingAnchor.constraint(
                equalTo: resumePreviewPanel.trailingAnchor,
                constant: -24
            ),
            resumePreviewButton.topAnchor.constraint(
                equalTo: resumePreviewPanel.topAnchor,
                constant: 16
            ),
            resumePreviewButton.bottomAnchor.constraint(
                equalTo: resumePreviewPanel.bottomAnchor,
                constant: -16
            ),
        ])
    }

    private func updatePreviewState(_ state: DisplayPreviewState) {
        onPreviewStateChanged?()

        switch state {
        case .running, .stopped:
            resumePreviewPanel.isHidden = true
        case .starting:
            resumePreviewPanel.isHidden = true
        case .reconnecting:
            resumePreviewButton.title = "Reconnecting Preview…"
            resumePreviewButton.isEnabled = false
            resumePreviewPanel.isHidden = false
        case .failed, .pausedByUser, .permissionRequired:
            resumePreviewButton.title = "Resume Preview"
            resumePreviewButton.isEnabled = true
            resumePreviewPanel.isHidden = false
        }
    }

    private func updateScreenConfiguration(_ configuration: ScreenConfigurationSnapshot) {
        guard configuration.resolution != .zero else {
            return
        }

        previousResolution = configuration.resolution
        view.window?.setContentSize(configuration.resolution)
        view.window?.contentAspectRatio = configuration.resolution
        view.window?.center()
        view.layer?.contentsScale = view.window?.backingScaleFactor ?? 1
        view.layer?.contentsGravity = .resize
        onResolutionChanged?()
    }

    private func updateWindowHighlight(_ isMouseInside: Bool) {
        guard isMouseInside != isWindowHighlighted else {
            return
        }

        isWindowHighlighted = isMouseInside
        view.window?.backgroundColor = isMouseInside
            ? NSColor(named: "TitleBarActive")
            : NSColor(named: "TitleBarInactive")
        if isMouseInside, bringsWindowToFront {
            view.window?.orderFrontRegardless()
        }
    }
}
