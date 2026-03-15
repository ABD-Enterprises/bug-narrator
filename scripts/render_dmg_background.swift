#!/usr/bin/env swift

import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/bugnarrator-dmg-background.png"
let canvasSize = NSSize(width: 680, height: 420)

let image = NSImage(size: canvasSize)
image.lockFocus()

NSColor(calibratedWhite: 0.975, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let topGlowRect = NSRect(x: 0, y: canvasSize.height * 0.55, width: canvasSize.width, height: canvasSize.height * 0.45)
let topGlow = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.55),
    NSColor(calibratedWhite: 1.0, alpha: 0.0),
])!
topGlow.draw(in: topGlowRect, angle: 90)

let arrowPath = NSBezierPath()
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.lineWidth = 10
arrowPath.move(to: NSPoint(x: canvasSize.width * 0.47, y: canvasSize.height * 0.60))
arrowPath.line(to: NSPoint(x: canvasSize.width * 0.53, y: canvasSize.height * 0.50))
arrowPath.line(to: NSPoint(x: canvasSize.width * 0.47, y: canvasSize.height * 0.40))

NSColor(calibratedWhite: 0.22, alpha: 0.85).setStroke()
arrowPath.stroke()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("error: failed to create DMG background image\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true,
    attributes: nil
)
try pngData.write(to: outputURL)
