import ScreenCaptureKit

enum ScreenCaptureAuthorization {
    static func verify() async throws {
        _ = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
    }
}
