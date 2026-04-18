#!/usr/bin/env swift
import AppKit

let outputPath = "/Users/ben/code/plant-app/Plants/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

let size = CGSize(width: 1024, height: 1024)
let background = NSColor.white
let leafColor = NSColor(calibratedRed: 0.17, green: 0.66, blue: 0.29, alpha: 1.0)

let config = NSImage.SymbolConfiguration(pointSize: 620, weight: .semibold)
guard let symbol = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else {
    fputs("Failed to load SF Symbol\n", stderr)
    exit(1)
}

let tinted = NSImage(size: symbol.size, flipped: false) { rect in
    symbol.draw(in: rect)
    leafColor.set()
    rect.fill(using: .sourceAtop)
    return true
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap\n", stderr)
    exit(1)
}
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
ctx.imageInterpolation = .high
ctx.shouldAntialias = true
NSGraphicsContext.current = ctx

background.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let drawSize = tinted.size
let origin = NSPoint(
    x: (size.width - drawSize.width) / 2,
    y: (size.height - drawSize.height) / 2
)
tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath) (\(png.count) bytes)")
