import Cocoa

final class GeneralSettingsViewController: NSViewController {
    var onSettingsChanged: ((GeneralSettings) -> Void)?

    private let preferences: GeneralPreferences
    private let resolutionPopup = NSPopUpButton()
    private let bringToFrontCheckbox = NSButton(
        checkboxWithTitle: "Bring the DisplayCove window forward when the pointer enters",
        target: nil,
        action: nil
    )
    private let previewCursorCheckbox = NSButton(
        checkboxWithTitle: "Show the cursor in the DisplayCove preview",
        target: nil,
        action: nil
    )
    private let preserveHDRCheckbox = NSButton(
        checkboxWithTitle: "Restore physical display HDR after creating a screen",
        target: nil,
        action: nil
    )

    init(preferences: GeneralPreferences = .shared) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        title = "General"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()

        let supportedResolutions = Array(Set(
            DisplaySessionConfiguration.standard().modes.map {
                DisplayResolution(width: $0.width, height: $0.height)
            }
        )).sorted {
            if $0.width == $1.width {
                return $0.height > $1.height
            }
            return $0.width > $1.width
        }

        for resolution in supportedResolutions {
            resolutionPopup.addItem(withTitle: resolution.displayName)
            resolutionPopup.lastItem?.representedObject = resolution
        }

        [
            resolutionPopup,
            bringToFrontCheckbox,
            previewCursorCheckbox,
            preserveHDRCheckbox,
        ].forEach {
            $0.target = self
            $0.action = #selector(settingsChanged)
        }

        let resolutionLabel = NSTextField(labelWithString: "Default resolution:")
        resolutionLabel.alignment = .left
        resolutionLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        resolutionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let resolutionRow = NSStackView(views: [
            resolutionLabel,
            resolutionPopup,
        ])
        resolutionRow.orientation = .horizontal
        resolutionRow.alignment = .centerY
        resolutionRow.spacing = 16

        let optionsStack = NSStackView(views: [
            bringToFrontCheckbox,
            previewCursorCheckbox,
            preserveHDRCheckbox,
        ])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 10

        let contentStack = NSStackView(views: [
            resolutionRow,
            optionsStack,
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
        ])

        loadSettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadSettings()
    }

    private func loadSettings() {
        let settings = preferences.settings
        resolutionPopup.selectItem(
            at: resolutionPopup.itemArray.firstIndex(where: {
                ($0.representedObject as? DisplayResolution) ==
                    settings.defaultResolution
            }) ?? 0
        )
        bringToFrontCheckbox.state = settings.bringsWindowToFront ? .on : .off
        previewCursorCheckbox.state = settings.showsPreviewCursor ? .on : .off
        preserveHDRCheckbox.state = settings.preservesPhysicalHDR ? .on : .off
    }

    @objc private func settingsChanged() {
        guard
            let resolution =
            resolutionPopup.selectedItem?.representedObject as? DisplayResolution
        else {
            return
        }

        let settings = GeneralSettings(
            defaultResolution: resolution,
            bringsWindowToFront: bringToFrontCheckbox.state == .on,
            showsPreviewCursor: previewCursorCheckbox.state == .on,
            preservesPhysicalHDR: preserveHDRCheckbox.state == .on
        )
        preferences.settings = settings
        onSettingsChanged?(settings)
    }
}
