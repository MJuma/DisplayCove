import Cocoa
import UniformTypeIdentifiers

@MainActor
final class RecordingCoordinator {
    var onError: ((Error, NSWindow?) -> Void)?
    var onStateChanged: (() -> Void)?

    private let preferences: RecordingPreferences

    init(preferences: RecordingPreferences) {
        self.preferences = preferences
    }

    func startRecording(for displayWindow: ManagedDisplayWindow?) {
        guard let displayWindow else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save DisplayCove Recording"
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first
        panel.nameFieldStringValue = defaultRecordingFilename(
            serialNumber: displayWindow.serialNumber
        )

        panel.beginSheetModal(for: displayWindow.window) { [weak self] response in
            guard
                response == .OK,
                let outputURL = panel.url,
                let self
            else {
                return
            }

            let settings = preferences.settings
            Task {
                do {
                    try await displayWindow.viewController.startRecording(
                        to: outputURL,
                        settings: settings
                    )
                } catch {
                    onError?(error, displayWindow.window)
                }
                onStateChanged?()
            }
        }
    }

    func stopRecording(for displayWindow: ManagedDisplayWindow?) {
        guard let displayWindow else {
            return
        }

        Task {
            do {
                try await displayWindow.viewController.stopRecording()
            } catch {
                onError?(error, displayWindow.window)
            }
            onStateChanged?()
        }
    }

    private func defaultRecordingFilename(serialNumber: UInt32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let displayName = DisplaySessionConfiguration.standard(
            serialNumber: serialNumber
        ).name
        return "\(displayName) \(formatter.string(from: Date())).mov"
    }
}
