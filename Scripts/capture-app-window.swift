#!/usr/bin/env swift

import AppKit
import Foundation
import ScreenCaptureKit

guard CommandLine.arguments.count == 4 else {
    fputs(
        "Usage: capture-app-window.swift <owner> <window-title> <output.png>\n",
        stderr
    )
    exit(2)
}

let ownerName = CommandLine.arguments[1]
let windowTitle = CommandLine.arguments[2]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
_ = NSApplication.shared

let shareableContent = try await SCShareableContent.excludingDesktopWindows(
    false,
    onScreenWindowsOnly: true
)
guard let window = shareableContent.windows.first(where: {
    $0.owningApplication?.applicationName == ownerName &&
        $0.title == windowTitle
}) else {
    fputs("No matching window found.\n", stderr)
    exit(1)
}

let configuration = SCStreamConfiguration()
configuration.width = Int(window.frame.width)
configuration.height = Int(window.frame.height)
configuration.showsCursor = false

let image: CGImage = try await withCheckedThrowingContinuation { continuation in
    SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(desktopIndependentWindow: window),
        configuration: configuration
    ) { image, error in
        if let image {
            continuation.resume(returning: image)
        } else {
            continuation.resume(
                throwing: error ?? CocoaError(.fileReadUnknown)
            )
        }
    }
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("The captured window could not be encoded.\n", stderr)
    exit(1)
}

try data.write(to: outputURL)
print(outputURL.path)
