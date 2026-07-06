#!/usr/bin/swift
// Generates macos/Resources/AppIcon.icns from an SF Symbol (no design tool
// dependency). Placeholder icon: reuses "display.2", the same glyph already
// shown in the menu bar (AppState.menuBarSymbol) — swap SYMBOL_NAME here and
// rerun once real branding lands (root STATE.md pendência "nome final do
// produto").
//
// Usage: swift macos/Scripts/make-icon.swift

import AppKit

let symbolName = "display.2.fill"
let fallbackSymbolName = "display.2"
let backgroundTop = NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.94, alpha: 1.0)
let backgroundBottom = NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.62, alpha: 1.0)

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let resourcesDir = scriptDir.appendingPathComponent("../Resources").standardized
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func symbolImage(pointSize: CGFloat) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        return img
    }
    return NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
}

/// White-tinted glyph, rendered on its own transparent canvas first. Tinting
/// via `sourceAtop` must happen BEFORE compositing onto the (opaque) icon
/// background: once behind an opaque fill, every pixel in the glyph's
/// bounding rect reads back destination-alpha=1 (bezel, screen fill AND the
/// transparent gaps between them alike), so the tint whites out the whole
/// rectangle instead of just the glyph shape.
func tintedGlyph(pointSize: CGFloat) -> NSImage {
    let glyph = symbolImage(pointSize: pointSize)
    let size = glyph.size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width)), pixelsHigh: Int(ceil(size.height)),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let rect = NSRect(origin: .zero, size: size)
    glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSColor.white.set()
    rect.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    let tinted = NSImage(size: size)
    tinted.addRepresentation(rep)
    return tinted
}

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237 // macOS "squircle" continuous-corner proportion
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let gradient = NSGradient(starting: backgroundTop, ending: backgroundBottom)
    gradient?.draw(in: path, angle: -90)

    let glyph = tintedGlyph(pointSize: size * 0.5)
    let glyphSize = glyph.size
    let scale = min(size * 0.62 / glyphSize.width, size * 0.62 / glyphSize.height)
    let drawSize = NSSize(width: glyphSize.width * scale, height: glyphSize.height * scale)
    let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
    let finalRect = NSRect(origin: origin, size: drawSize)
    glyph.draw(in: finalRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in sizes {
    let rep = renderIcon(size: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(name)")
    }
    try! data.write(to: iconsetDir.appendingPathComponent("\(name).png"))
}

let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try! process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}
try? FileManager.default.removeItem(at: iconsetDir)
print("OK: \(icnsPath.path)")
