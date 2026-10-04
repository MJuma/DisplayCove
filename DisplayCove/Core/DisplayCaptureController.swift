import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

@MainActor
final class DisplayCaptureController: NSObject {
    var onFrameAvailable: ((IOSurface) -> Void)?
    var onStopped: ((Error) -> Void)?

    private let outputQueue = DispatchQueue(
        label: "dev.juma.DisplayCove.display-capture",
        qos: .userInteractive
    )
    private var stream: SCStream?

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

        let streamConfiguration = makeStreamConfiguration(
            configuration: configuration,
            showsCursor: showsCursor
        )
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
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

    func stop() async {
        guard let stream else {
            return
        }

        self.stream = nil
        try? await stream.stopCapture()
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

private struct UncheckedSendableValue<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
