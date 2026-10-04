import OSLog

enum AppLog {
    private static let subsystem = "dev.juma.DisplayCove"

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
