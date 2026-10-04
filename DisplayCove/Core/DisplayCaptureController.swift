import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

enum DisplayCapturePickerError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        "Display selection was cancelled."
    }
}

@MainActor
final class DisplayCaptureController: NSObject {
    var onFrameAvailable: ((IOSurface) -> Void)?
    var onStopped: ((Error) -> Void)?

    private let outputQueue = DispatchQueue(
        label: "dev.juma.DisplayCove.display-capture",
        qos: .userInteractive
    )
    private var stream: SCStream?
    private var pickerContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        SCContentSharingPicker.shared.add(self)
    }

    deinit {
        SCContentSharingPicker.shared.remove(self)
    }

    func start(
        displayID: CGDirectDisplayID,
        configuration: ScreenConfigurationSnapshot,
        showsCursor: Bool
    ) async throws {
        await stop()

        let shareableContent =
            try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        guard let display = shareableContent.displays.first(where: {
            $0.displayID == displayID
        }) else {
            throw DisplaySessionError.displayUnavailable
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        try await start(
            filter: filter,
            configuration: configuration,
            showsCursor: showsCursor
        )
    }

    private func start(
        filter: SCContentFilter,
        configuration: ScreenConfigurationSnapshot,
        showsCursor: Bool
    ) async throws {
        let streamConfiguration = makeStreamConfiguration(
            configuration: configuration,
            showsCursor: showsCursor
        )
        let stream = SCStream(
            filter: filter,
            configuration: streamConfiguration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: outputQueue
        )

        self.stream = stream
        try await stream.startCapture()
    }

    func update(
        configuration: ScreenConfigurationSnapshot,
        showsCursor: Bool
    ) async throws {
        guard let stream else {
            return
        }

        try await stream.updateConfiguration(
            makeStreamConfiguration(
                configuration: configuration,
                showsCursor: showsCursor
            )
        )
    }

    func startUsingPicker(
        displayID: CGDirectDisplayID,
        configuration: ScreenConfigurationSnapshot,
        showsCursor: Bool
    ) async throws {
        await stop()
        try await authorizeUsingPicker()
        try await start(
            displayID: displayID,
            configuration: configuration,
            showsCursor: showsCursor
        )
    }

    private func authorizeUsingPicker() async throws {
        guard pickerContinuation == nil else {
            throw DisplayCapturePickerError.cancelled
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            pickerContinuation = continuation

            let picker = SCContentSharingPicker.shared
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = [.singleDisplay]
            configuration.allowsChangingSelectedContent = false
            picker.defaultConfiguration = configuration
            picker.maximumStreamCount = 1
            picker.isActive = true
            picker.present(using: .display)
        }
    }

    func stop() async {
        failPicker(with: DisplayCapturePickerError.cancelled)

        guard let stream else {
            return
        }

        self.stream = nil
        try? await stream.stopCapture()
    }

    private func finishPicker() {
        guard let pickerContinuation else {
            return
        }

        self.pickerContinuation = nil
        SCContentSharingPicker.shared.isActive = false
        pickerContinuation.resume(returning: ())
    }

    private func failPicker(with error: Error) {
        guard let pickerContinuation else {
            return
        }

        self.pickerContinuation = nil
        SCContentSharingPicker.shared.isActive = false
        pickerContinuation.resume(throwing: error)
    }

    private func makeStreamConfiguration(
        configuration: ScreenConfigurationSnapshot,
        showsCursor: Bool
    ) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = Int(
            configuration.resolution.width * configuration.scaleFactor
        )
        streamConfiguration.height = Int(
            configuration.resolution.height * configuration.scaleFactor
        )
        streamConfiguration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: 60
        )
        streamConfiguration.queueDepth = 5
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = showsCursor
        streamConfiguration.scalesToFit = true
        return streamConfiguration
    }
}

extension DisplayCaptureController: SCStreamOutput {
    nonisolated func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard
            type == .screen,
            sampleBuffer.isValid,
            let imageBuffer = sampleBuffer.imageBuffer,
            let surface = CVPixelBufferGetIOSurface(imageBuffer)?
            .takeUnretainedValue()
        else {
            return
        }

        let sendableSurface = UncheckedSendableValue(surface)
        Task { @MainActor [weak self] in
            self?.onFrameAvailable?(sendableSurface.value)
        }
    }
}

extension DisplayCaptureController: SCStreamDelegate {
    nonisolated func stream(_: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.stream = nil
            self?.onStopped?(error)
        }
    }
}

extension DisplayCaptureController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _: SCContentSharingPicker,
        didCancelFor _: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.failPicker(with: DisplayCapturePickerError.cancelled)
        }
    }

    nonisolated func contentSharingPicker(
        _: SCContentSharingPicker,
        didUpdateWith _: SCContentFilter,
        for _: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.finishPicker()
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(
        _ error: any Error
    ) {
        let error = UncheckedSendableValue(error)
        Task { @MainActor [weak self] in
            self?.failPicker(with: error.value)
        }
    }
}

private struct UncheckedSendableValue<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
