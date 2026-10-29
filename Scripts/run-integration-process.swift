import Darwin
import Foundation

struct IntegrationRunnerError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

func stop(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    let deadline = ContinuousClock.now + .seconds(2)
    while process.isRunning, ContinuousClock.now < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
}

func run(logURL: URL) throws -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 4, let timeout = Double(arguments[1]),
          timeout.isFinite, (0.1 ... 600).contains(timeout),
          ["lifecycle", "recording"].contains(arguments[2])
    else {
        throw IntegrationRunnerError(message: "Expected timeout (0.1...600), lifecycle/recording, and an isolated executable.")
    }
    let mode = arguments[2]
    let executable = URL(fileURLWithPath: arguments[3]).standardizedFileURL
    let identifier = "dev.juma.DisplayCove.\(mode)-integration"
    let infoURL = executable.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Info.plist")
    let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL), format: nil
    ) as? [String: Any]
    guard info?["CFBundleIdentifier"] as? String == identifier else {
        throw IntegrationRunnerError(message: "Refusing to launch a production or incorrectly identified app.")
    }
    var environment = ProcessInfo.processInfo.environment
    let runID = UUID().uuidString
    environment["DISPLAYCOVE_INTEGRATION_RUN_ID"] = runID
    environment.removeValue(forKey: "DISPLAYCOVE_LIFECYCLE_TEST")
    environment.removeValue(forKey: "DISPLAYCOVE_RECORDING_TEST_OUTPUT")
    if mode == "lifecycle" {
        environment["DISPLAYCOVE_LIFECYCLE_TEST"] = "1"
        environment.removeValue(forKey: "DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT")
    } else {
        environment["DISPLAYCOVE_RECORDING_TEST_OUTPUT"] = "1"
        for (key, value) in [
            "DURATION": "1", "CODEC": "hevc", "FRAME_RATE": "60",
            "QUALITY": "compact", "SYSTEM_AUDIO": "1",
        ] where environment["DISPLAYCOVE_RECORDING_TEST_\(key)"] == nil {
            environment["DISPLAYCOVE_RECORDING_TEST_\(key)"] = value
        }
    }
    guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
        throw IntegrationRunnerError(message: "Could not create the private integration log.")
    }
    let log = try FileHandle(forWritingTo: logURL)
    let process = Process()
    process.executableURL = executable
    process.environment = environment
    process.standardOutput = log
    process.standardError = log
    try process.run()
    defer { stop(process) }
    let deadline = ContinuousClock.now + .seconds(timeout)
    while process.isRunning, ContinuousClock.now < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning
    if timedOut {
        stop(process)
    }
    process.waitUntilExit()
    try log.synchronize()
    try log.close()
    let output = try String(contentsOf: logURL, encoding: .utf8)
    FileHandle.standardOutput.write(Data(output.utf8))
    let keep = mode == "recording" && environment["DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT"] == "1"
    if !keep, let line = output.split(separator: "\n").first(where: {
        $0.hasPrefix("DISPLAYCOVE_INTEGRATION_DIRECTORY=")
    }) {
        let path = String(line.dropFirst("DISPLAYCOVE_INTEGRATION_DIRECTORY=".count))
        let directory = URL(fileURLWithPath: path).standardizedFileURL
        guard directory.lastPathComponent == "displaycove-integration-\(runID)" else {
            throw IntegrationRunnerError(message: "Refusing to clean an unexpected integration directory.")
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw IntegrationRunnerError(message: "Refusing a symbolic-link integration directory.")
            }
            try FileManager.default.removeItem(at: directory)
        }
    }
    if timedOut {
        throw IntegrationRunnerError(message: "Integration process exceeded \(timeout) seconds and was stopped.")
    }
    let prefix = mode == "lifecycle" ? "DISPLAYCOVE_LIFECYCLE" : "DISPLAYCOVE_RECORDING"
    guard process.terminationStatus == 0,
          output.split(separator: "\n").contains(Substring("\(prefix)_INTEGRATION_SUCCESS"))
    else {
        throw IntegrationRunnerError(message: "Integration failed (status \(process.terminationStatus)) or did not report success.")
    }
    return 0
}

let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("DisplayCove-Runner.\(UUID().uuidString)")
var status: Int32 = 1
do {
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    status = try run(logURL: fixture.appendingPathComponent("process.log"))
} catch {
    FileHandle.standardError.write(Data("Integration runner failed: \(error.localizedDescription)\n".utf8))
}

do {
    if FileManager.default.fileExists(atPath: fixture.path) {
        try FileManager.default.removeItem(at: fixture)
    }
} catch {
    FileHandle.standardError.write(Data("Integration log cleanup failed: \(error.localizedDescription)\n".utf8))
    status = 1
}

exit(status)
