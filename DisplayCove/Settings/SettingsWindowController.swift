import Cocoa

final class SettingsWindowController: NSWindowController {
    init(
        generalPreferences: GeneralPreferences = .shared,
        recordingPreferences: RecordingPreferences = .shared,
        onGeneralSettingsChanged: @escaping (GeneralSettings) -> Void
    ) {
        let generalViewController = GeneralSettingsViewController(
            preferences: generalPreferences
        )
        generalViewController.onSettingsChanged = onGeneralSettingsChanged

        let recordingViewController = RecordingSettingsViewController(
            preferences: recordingPreferences
        )

        let contentViewController = SettingsContentViewController(
            generalViewController: generalViewController,
            recordingViewController: recordingViewController
        )
        let hasSettingsIssue = generalPreferences.persistenceError != nil ||
            recordingPreferences.persistenceError != nil
        let contentSize = NSSize(width: 560, height: hasSettingsIssue ? 510 : 390)
        contentViewController.preferredContentSize = contentSize

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DisplayCove Settings"
        window.contentViewController = contentViewController
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class PreferencesRecoveryView: NSStackView {
    private let message = NSTextField(wrappingLabelWithString: "")
    private var onReset: (() -> Void)?

    init(onReset: @escaping () -> Void) {
        self.onReset = onReset
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8
        message.textColor = .systemOrange
        message.font = .systemFont(ofSize: 12)
        message.preferredMaxLayoutWidth = 480
        let reset = NSButton(title: "Reset saved settings...", target: self, action: #selector(resetPressed))
        addArrangedSubview(message)
        addArrangedSubview(reset)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ issue: String?) {
        message.stringValue = issue ?? ""
        isHidden = issue == nil
    }

    @objc private func resetPressed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset these saved settings?"
        alert.informativeText = "This replaces the preserved settings for this tab with defaults. It cannot be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onReset?()
        }
    }
}

private final class SettingsContentViewController: NSViewController {
    private let generalViewController: NSViewController
    private let recordingViewController: NSViewController
    private let tabSelector = NSSegmentedControl(
        labels: ["General", "Recording"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    init(
        generalViewController: NSViewController,
        recordingViewController: NSViewController
    ) {
        self.generalViewController = generalViewController
        self.recordingViewController = recordingViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()

        tabSelector.selectedSegment = 0
        tabSelector.target = self
        tabSelector.action = #selector(tabChanged)
        tabSelector.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabSelector)

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        addChild(generalViewController)
        addChild(recordingViewController)

        for childViewController in [
            generalViewController,
            recordingViewController,
        ] {
            let childView = childViewController.view
            childView.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(childView)
            NSLayoutConstraint.activate([
                childView.leadingAnchor.constraint(
                    equalTo: contentContainer.leadingAnchor
                ),
                childView.trailingAnchor.constraint(
                    equalTo: contentContainer.trailingAnchor
                ),
                childView.topAnchor.constraint(
                    equalTo: contentContainer.topAnchor
                ),
                childView.bottomAnchor.constraint(
                    equalTo: contentContainer.bottomAnchor
                ),
            ])
        }

        recordingViewController.view.isHidden = true

        NSLayoutConstraint.activate([
            tabSelector.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            tabSelector.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentContainer.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            contentContainer.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            contentContainer.topAnchor.constraint(
                equalTo: tabSelector.bottomAnchor,
                constant: 12
            ),
            contentContainer.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            ),
        ])
    }

    @objc private func tabChanged() {
        let showsGeneral = tabSelector.selectedSegment == 0
        generalViewController.view.isHidden = !showsGeneral
        recordingViewController.view.isHidden = showsGeneral
    }
}
