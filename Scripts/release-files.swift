import Foundation

struct ReleaseFilesError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .resolvingSymlinksInPath()
let dist = root.appendingPathComponent("dist", isDirectory: true)
let arguments = CommandLine.arguments

func checkedURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
        throw ReleaseFilesError(message: "Refusing a symbolic-link workspace.")
    }
    return url
}

do {
    guard arguments.count >= 3 else { throw ReleaseFilesError(message: "Missing operation or path.") }
    let url = try checkedURL(arguments[2])
    switch arguments[1] {
    case "cleanup-workspace", "cleanup-integration-build":
        let prefix = arguments[1] == "cleanup-workspace" ? "DisplayCove-Release." : "DisplayCove-Integration."
        guard arguments.count == 3, url.lastPathComponent.hasPrefix(prefix) else {
            throw ReleaseFilesError(message: "Unexpected release workspace.")
        }
        try manager.removeItem(at: url)
    case "cleanup-stage", "publish":
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == dist,
              url.lastPathComponent.hasPrefix(".displaycove-release.")
        else {
            throw ReleaseFilesError(message: "Unexpected artifact staging path.")
        }
        if arguments[1] == "cleanup-stage" {
            guard arguments.count == 3 else { throw ReleaseFilesError(message: "Unexpected arguments.") }
            try manager.removeItem(at: url)
        } else {
            guard arguments.count == 4 else { throw ReleaseFilesError(message: "Missing destination.") }
            let destination = URL(fileURLWithPath: arguments[3]).standardizedFileURL
            guard destination.deletingLastPathComponent().resolvingSymlinksInPath() == dist,
                  destination.lastPathComponent.range(
                      of: #"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-dev)?$"#,
                      options: .regularExpression
                  ) != nil
            else {
                throw ReleaseFilesError(message: "Unexpected release destination.")
            }
            try manager.moveItem(at: url, to: destination)
        }
    default:
        throw ReleaseFilesError(message: "Unknown operation.")
    }
} catch {
    FileHandle.standardError.write(Data("Release file operation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
