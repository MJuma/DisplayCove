#!/usr/bin/env swift

import AppKit
import Foundation

private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let appIconURL = rootURL
    .appendingPathComponent("DisplayCove/Assets.xcassets/AppIcon.appiconset")
private let iconSourceURL = rootURL.appendingPathComponent("Icon")
private let marketingURL = rootURL.appendingPathComponent("Marketing")

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        deviceRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func makeBitmap(
    width: Int,
    height: Int,
    draw: () -> Void
) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

private func drawIcon(size: Int) -> NSBitmapImageRep {
    makeBitmap(width: size, height: size) {
        let scale = CGFloat(size) / 1024
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        let outerShadow = NSShadow()
        outerShadow.shadowColor = color(0x00101E, alpha: 0.45)
        outerShadow.shadowBlurRadius = 34
        outerShadow.shadowOffset = NSSize(width: 0, height: -18)
        outerShadow.set()

        let tile = NSBezierPath(
            roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
            xRadius: 206,
            yRadius: 206
        )
        NSGradient(
            starting: color(0x0B4F6C),
            ending: color(0x06182F)
        )!.draw(in: tile, angle: 92)
        NSGraphicsContext.restoreGraphicsState()

        let tileHighlight = NSBezierPath(
            roundedRect: NSRect(x: 88, y: 510, width: 848, height: 420),
            xRadius: 180,
            yRadius: 180
        )
        color(0x39D6C8, alpha: 0.08).setFill()
        tileHighlight.fill()

        NSGraphicsContext.saveGraphicsState()
        let coveShadow = NSShadow()
        coveShadow.shadowColor = color(0x001B2A, alpha: 0.65)
        coveShadow.shadowBlurRadius = 30
        coveShadow.shadowOffset = NSSize(width: 0, height: -12)
        coveShadow.set()

        let cove = NSBezierPath()
        cove.move(to: NSPoint(x: 176, y: 330))
        cove.curve(
            to: NSPoint(x: 848, y: 330),
            controlPoint1: NSPoint(x: 176, y: 790),
            controlPoint2: NSPoint(x: 848, y: 790)
        )
        cove.lineWidth = 92
        cove.lineCapStyle = .round
        color(0x11B8B2).setStroke()
        cove.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let coveHighlight = NSBezierPath()
        coveHighlight.move(to: NSPoint(x: 190, y: 342))
        coveHighlight.curve(
            to: NSPoint(x: 834, y: 342),
            controlPoint1: NSPoint(x: 190, y: 742),
            controlPoint2: NSPoint(x: 834, y: 742)
        )
        coveHighlight.lineWidth = 16
        coveHighlight.lineCapStyle = .round
        color(0x7AF3E4, alpha: 0.72).setStroke()
        coveHighlight.stroke()

        NSGraphicsContext.saveGraphicsState()
        let screenShadow = NSShadow()
        screenShadow.shadowColor = color(0x00101E, alpha: 0.75)
        screenShadow.shadowBlurRadius = 34
        screenShadow.shadowOffset = NSSize(width: 0, height: -18)
        screenShadow.set()

        let screenFrame = NSBezierPath(
            roundedRect: NSRect(x: 190, y: 300, width: 644, height: 384),
            xRadius: 62,
            yRadius: 62
        )
        NSGradient(
            starting: color(0x163E54),
            ending: color(0x071724)
        )!.draw(in: screenFrame, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        let display = NSBezierPath(
            roundedRect: NSRect(x: 224, y: 344, width: 576, height: 304),
            xRadius: 38,
            yRadius: 38
        )
        NSGradient(
            starting: color(0x1DD7CF),
            ending: color(0x0A5C7E)
        )!.draw(in: display, angle: 78)

        let displayGlow = NSBezierPath(
            roundedRect: NSRect(x: 246, y: 494, width: 532, height: 130),
            xRadius: 30,
            yRadius: 30
        )
        color(0xB8FFF4, alpha: 0.13).setFill()
        displayGlow.fill()

        let workspace = NSBezierPath(
            roundedRect: NSRect(x: 274, y: 388, width: 476, height: 202),
            xRadius: 25,
            yRadius: 25
        )
        color(0xE9FFFC, alpha: 0.82).setFill()
        workspace.fill()

        let workspaceHeader = NSBezierPath(
            roundedRect: NSRect(x: 274, y: 544, width: 476, height: 46),
            xRadius: 25,
            yRadius: 25
        )
        color(0xFFFFFF, alpha: 0.52).setFill()
        workspaceHeader.fill()

        let stand = NSBezierPath(
            roundedRect: NSRect(x: 484, y: 250, width: 56, height: 70),
            xRadius: 18,
            yRadius: 18
        )
        color(0x0B293B).setFill()
        stand.fill()

        let base = NSBezierPath(
            roundedRect: NSRect(x: 408, y: 232, width: 208, height: 34),
            xRadius: 17,
            yRadius: 17
        )
        color(0x0A2232).setFill()
        base.fill()
    }
}

private func drawSocialPreview(iconURL: URL) throws -> NSBitmapImageRep {
    let icon = NSImage(contentsOf: iconURL)!

    return makeBitmap(width: 1280, height: 640) {
        let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1280, height: 640))
        NSGradient(
            starting: color(0x0C4C68),
            ending: color(0x061528)
        )!.draw(in: background, angle: 8)

        let glow = NSBezierPath(ovalIn: NSRect(x: -80, y: 40, width: 650, height: 650))
        color(0x19C9BE, alpha: 0.12).setFill()
        glow.fill()

        icon.draw(
            in: NSRect(x: 90, y: 100, width: 440, height: 440),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        let title = "DisplayCove" as NSString
        title.draw(
            at: NSPoint(x: 580, y: 370),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 78, weight: .bold),
                .foregroundColor: NSColor.white,
                .kern: -1.5,
            ]
        )

        let tagline = "A dedicated desktop for every share." as NSString
        tagline.draw(
            in: NSRect(x: 584, y: 245, width: 610, height: 90),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .medium),
                .foregroundColor: color(0xC9FFF7),
            ]
        )
    }
}

try fileManager.createDirectory(at: appIconURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconSourceURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: marketingURL, withIntermediateDirectories: true)

let iconFiles = [
    ("Icon-16.png", 16),
    ("Icon-32.png", 32),
    ("Icon-33.png", 32),
    ("Icon-64.png", 64),
    ("Icon-128.png", 128),
    ("Icon-256.png", 256),
    ("Icon-257.png", 256),
    ("Icon-512.png", 512),
    ("Icon-513.png", 512),
    ("Icon-1024.png", 1024),
]

for (filename, size) in iconFiles {
    try writePNG(
        drawIcon(size: size),
        to: appIconURL.appendingPathComponent(filename)
    )
}

let masterIconURL = iconSourceURL.appendingPathComponent("DisplayCove-1024.png")
try writePNG(drawIcon(size: 1024), to: masterIconURL)
try writePNG(
    drawSocialPreview(iconURL: masterIconURL),
    to: marketingURL.appendingPathComponent("GitHub-Social-Preview.png")
)

print("Generated DisplayCove icon and marketing assets.")
