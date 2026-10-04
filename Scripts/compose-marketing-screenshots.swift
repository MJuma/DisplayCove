#!/usr/bin/env swift

import AppKit
import Foundation

private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let capturesURL = rootURL.appendingPathComponent("Marketing/Captures")
private let screenshotsURL = rootURL.appendingPathComponent("Marketing/Screenshots")

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        deviceRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func drawWindow(_ image: NSImage, in rect: NSRect, cornerRadius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowColor = color(0x000A14, alpha: 0.65)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()

    let shape = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    color(0x06182F).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    image.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func drawPill(_ text: String, at point: NSPoint) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: color(0xD6FFF8),
    ]
    let label = text as NSString
    let labelSize = label.size(withAttributes: attributes)
    let pillRect = NSRect(
        x: point.x,
        y: point.y,
        width: labelSize.width + 34,
        height: 38
    )
    let pill = NSBezierPath(
        roundedRect: pillRect,
        xRadius: 19,
        yRadius: 19
    )
    color(0x0D566B, alpha: 0.96).setFill()
    pill.fill()
    label.draw(
        at: NSPoint(
            x: pillRect.minX + 17,
            y: pillRect.minY + 8
        ),
        withAttributes: attributes
    )
}

let largeDisplay = NSImage(
    contentsOf: capturesURL.appendingPathComponent("DisplayCove-1920x1080.png")
)!
let compactDisplay = NSImage(
    contentsOf: capturesURL.appendingPathComponent("DisplayCove-1280x720.png")
)!

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1600,
    pixelsHigh: 900,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = NSSize(width: 1600, height: 900)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1600, height: 900))
NSGradient(
    starting: color(0x0C4D69),
    ending: color(0x061528)
)!.draw(in: background, angle: 8)

let glow = NSBezierPath(ovalIn: NSRect(x: 840, y: -260, width: 900, height: 900))
color(0x1AC9BE, alpha: 0.1).setFill()
glow.fill()

("Multiple displays. One controlled workspace." as NSString).draw(
    at: NSPoint(x: 72, y: 780),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 42, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: -0.5,
    ]
)

("Create each virtual screen at the resolution its audience needs." as NSString).draw(
    at: NSPoint(x: 74, y: 735),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .regular),
        .foregroundColor: color(0xCDE6ED),
    ]
)

let largeRect = NSRect(x: 74, y: 70, width: 930, height: 603)
let compactRect = NSRect(x: 870, y: 52, width: 640, height: 422)
drawWindow(largeDisplay, in: largeRect, cornerRadius: 18)
drawWindow(compactDisplay, in: compactRect, cornerRadius: 16)
drawPill("1920 × 1080", at: NSPoint(x: 106, y: 94))
drawPill("1280 × 720", at: NSPoint(x: 900, y: 76))

NSGraphicsContext.restoreGraphicsState()

try fileManager.createDirectory(
    at: screenshotsURL,
    withIntermediateDirectories: true
)
let outputURL = screenshotsURL.appendingPathComponent(
    "DisplayCove-Multiple-Displays.png"
)
try bitmap.representation(using: .png, properties: [:])!.write(to: outputURL)
print(outputURL.path)
