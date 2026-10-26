#!/usr/bin/env swift
import AppKit
import Foundation

// Generates Resources/AppIcon.icns: a rounded gradient tile with a white thermometer.
// Run from the project root: swift scripts/make-icon.swift

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

func tintedSymbol(named name: String, pointSize: CGFloat) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return nil }

    let image = NSImage(size: symbol.size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(
        at: .zero,
        from: NSRect(origin: .zero, size: symbol.size),
        operation: .destinationIn,
        fraction: 1.0
    )
    image.unlockFocus()
    return image
}

func drawIcon(size: CGFloat) {
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tileRect = NSRect(x: 74, y: 74, width: 876, height: 876)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 200, yRadius: 200)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.70, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.20, blue: 0.24, alpha: 1)
    ])!
    gradient.draw(in: tile, angle: -90)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    tile.lineWidth = 4
    tile.stroke()

    guard let thermometer = tintedSymbol(named: "thermometer.medium", pointSize: 520) else { return }

    let desiredHeight: CGFloat = 560
    let aspect = thermometer.size.width / thermometer.size.height
    let desiredWidth = desiredHeight * aspect
    let symbolRect = NSRect(
        x: (1024 - desiredWidth) / 2,
        y: (1024 - desiredHeight) / 2 - 10,
        width: desiredWidth,
        height: desiredHeight
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    thermometer.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSShadow().set()

    let dot = NSBezierPath(ovalIn: NSRect(x: 760, y: 742, width: 22, height: 22))
    NSColor.white.withAlphaComponent(0.75).setFill()
    dot.fill()
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }
    rep.size = NSSize(width: 1024, height: 1024)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: 1024)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    try? fileManager.removeItem(at: iconset)
    print("Wrote \(output.path)")
} else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
