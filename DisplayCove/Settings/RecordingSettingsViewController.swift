import AVFoundation
import Cocoa

final class RecordingSettingsViewController: NSViewController {
    private let preferences: RecordingPreferences

    private let codecPopup = NSPopUpButton()
    private let frameRatePopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let cursorCheckbox = NSButton(
        checkboxWithTitle: "Show cursor",
        target: nil,
        action: nil
    )
    private let clicksCheckbox = NSButton(
        checkboxWithTitle: "Show mouse clicks",
        target: nil,
        action: nil
    )
    private let systemAudioCheckbox = NSButton(
        checkboxWithTitle: "Record system audio",
        target: nil,
        action: nil
    )
    private let microphoneCheckbox = NSButton(
        checkboxWithTitle: "Record microphone",
        target: nil,
        action: nil
    )
    private let microphonePopup = NSPopUpButton()

    init(preferences: RecordingPreferences = .shared) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        title = "Recording"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        configureControls()
        configureLayout()
        loadSettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loadMicrophones()
        loadSettings()
    }

    private func configureControls() {
        for codec in RecordingCodec.allCases {
            codecPopup.addItem(withTitle: codec.displayName)
            codecPopup.lastItem?.representedObject = codec.rawValue
        }
        for frameRate in RecordingFrameRate.allCases {
            frameRatePopup.addItem(withTitle: frameRate.displayName)
            frameRatePopup.lastItem?.representedObject = frameRate.rawValue
        }
        for quality in RecordingQuality.allCases {
            qualityPopup.addItem(withTitle: quality.displayName)
            qualityPopup.lastItem?.representedObject = quality.rawValue
        }

        [
            codecPopup,
            frameRatePopup,
            qualityPopup,
            cursorCheckbox,
            clicksCheckbox,
            systemAudioCheckbox,
            microphoneCheckbox,
            microphonePopup,
        ].forEach {
            $0.target = self
            $0.action = #selector(settingsChanged)
        }
    }

    private func configureLayout() {
        for item in [codecPopup, frameRatePopup, qualityPopup, microphonePopup] {
            item.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        }

        let videoOptions = NSStackView(views: [
            cursorCheckbox,
            clicksCheckbox,
        ])
        videoOptions.orientation = .vertical
        videoOptions.alignment = .leading
        videoOptions.spacing = 8

        let audioOptions = NSStackView(views: [
            systemAudioCheckbox,
            microphoneCheckbox,
            microphonePopup,
        ])
        audioOptions.orientation = .vertical
        audioOptions.alignment = .leading
        audioOptions.spacing = 8

        let contentStack = NSStackView(views: [
            makeLabeledRow(title: "Codec:", control: codecPopup),
            makeLabeledRow(title: "Frame rate:", control: frameRatePopup),
            makeLabeledRow(title: "Quality:", control: qualityPopup),
            makeLabeledRow(title: "Video:", control: videoOptions),
            makeLabeledRow(title: "Audio:", control: audioOptions),
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
        ])
    }

    private func makeLabeledRow(
        title: String,
        control: NSView
    ) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        return row
    }

    private func loadMicrophones() {
        microphonePopup.removeAllItems()
        microphonePopup.addItem(withTitle: "System Default")
        microphonePopup.lastItem?.representedObject = ""

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        for device in discoverySession.devices {
            microphonePopup.addItem(withTitle: device.localizedName)
            microphonePopup.lastItem?.representedObject = device.uniqueID
        }
    }

    private func loadSettings() {
        let settings = preferences.settings

        selectItem(in: codecPopup, representedObject: settings.codec.rawValue)
        selectItem(in: frameRatePopup, representedObject: settings.frameRate.rawValue)
        selectItem(in: qualityPopup, representedObject: settings.quality.rawValue)
        cursorCheckbox.state = settings.showsCursor ? .on : .off
        clicksCheckbox.state = settings.showsMouseClicks ? .on : .off
        systemAudioCheckbox.state = settings.capturesSystemAudio ? .on : .off
        microphoneCheckbox.state = settings.capturesMicrophone ? .on : .off
        selectItem(
            in: microphonePopup,
            representedObject: settings.microphoneDeviceID ?? ""
        )
        microphonePopup.isEnabled = settings.capturesMicrophone
    }

    private func selectItem(in popup: NSPopUpButton, representedObject: Any) {
        guard let index = popup.itemArray.firstIndex(where: {
            String(describing: $0.representedObject ?? "") ==
                String(describing: representedObject)
        }) else {
            popup.selectItem(at: 0)
            return
        }

        popup.selectItem(at: index)
    }

    @objc private func settingsChanged() {
        let microphoneDeviceID = microphonePopup.selectedItem?.representedObject as? String

        preferences.settings = RecordingSettings(
            codec: RecordingCodec(
                rawValue: codecPopup.selectedItem?.representedObject as? String ?? ""
            ) ?? .h264,
            frameRate: RecordingFrameRate(
                rawValue: frameRatePopup.selectedItem?.representedObject as? Int ?? 30
            ) ?? .thirty,
            quality: RecordingQuality(
                rawValue: qualityPopup.selectedItem?.representedObject as? String ?? ""
            ) ?? .native,
            showsCursor: cursorCheckbox.state == .on,
            showsMouseClicks: clicksCheckbox.state == .on,
            capturesSystemAudio: systemAudioCheckbox.state == .on,
            capturesMicrophone: microphoneCheckbox.state == .on,
            microphoneDeviceID: microphoneDeviceID?.isEmpty == false
                ? microphoneDeviceID
                : nil
        )
        microphonePopup.isEnabled = microphoneCheckbox.state == .on
    }
}
