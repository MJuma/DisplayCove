import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.juma.DisplayCove"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

    static let display = Logger(
        subsystem: subsystem,
        category: "display"
    )
    static let recording = Logger(
        subsystem: subsystem,
        category: "recording"
    )
    static let preferences = Logger(
        subsystem: subsystem,
        category: "preferences"
    )
}
