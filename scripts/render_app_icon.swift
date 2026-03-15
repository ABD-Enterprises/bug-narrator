#!/usr/bin/env swift

import AppKit

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "/Users/deffenda/Code/FeedbackMic/Resources/AppIconSource.png"

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func capsulePath(_ rect: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
}

func fill(_ path: NSBezierPath, with colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: path, angle: angle)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func drawLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor, alpha: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineCapStyle = .round
    path.lineWidth = width
    color.withAlphaComponent(alpha).setStroke()
    path.stroke()
}

func drawDot(center: CGPoint, radius: CGFloat, color: NSColor) {
    let path = NSBezierPath(ovalIn: rect(center.x - radius, center.y - radius, radius * 2, radius * 2))
    color.setFill()
    path.fill()
}

func withShadow(color: NSColor, blur: CGFloat, offset: CGSize = .zero, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

image.lockFocus()
guard let cgContext = NSGraphicsContext.current?.cgContext else {
    fatalError("Missing graphics context")
}

cgContext.setFillColor(NSColor.clear.cgColor)
cgContext.fill(CGRect(origin: .zero, size: size))

let canvas = rect(76, 90, 872, 872)
let background = roundedPath(canvas, radius: 150)

withShadow(color: NSColor(calibratedWhite: 0, alpha: 0.35), blur: 48, offset: CGSize(width: 0, height: -18)) {
    fill(background, with: [
        NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.12, alpha: 1)
    ], angle: -90)
}

let ambient = NSBezierPath(ovalIn: rect(150, 470, 730, 410))
fill(ambient, with: [
    NSColor(calibratedRed: 0.12, green: 0.47, blue: 0.95, alpha: 0.18),
    NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 0)
], angle: 0)

let topGlow = roundedPath(rect(86, 870, 852, 44), radius: 22)
fill(topGlow, with: [
    NSColor(calibratedRed: 0.16, green: 0.91, blue: 0.98, alpha: 0.95),
    NSColor(calibratedRed: 0.13, green: 0.48, blue: 1.0, alpha: 0.7),
    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.35, alpha: 0)
], angle: 0)

let bubbleTail = NSBezierPath()
bubbleTail.move(to: CGPoint(x: 325, y: 180))
bubbleTail.line(to: CGPoint(x: 285, y: 60))
bubbleTail.line(to: CGPoint(x: 425, y: 160))
bubbleTail.close()
fill(bubbleTail, with: [
    NSColor(calibratedRed: 0.12, green: 0.48, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.26, blue: 0.7, alpha: 1)
], angle: -55)

stroke(background, color: NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.15, alpha: 0.95), width: 12)
stroke(topGlow, color: NSColor.clear, width: 0)

let leftGuide = roundedPath(rect(165, 300, 16, 240), radius: 8)
fill(leftGuide, with: [
    NSColor(calibratedRed: 0.1, green: 0.74, blue: 0.88, alpha: 0.95),
    NSColor(calibratedRed: 0.11, green: 0.52, blue: 0.9, alpha: 0.7)
], angle: -90)

drawLine(from: CGPoint(x: 143, y: 686), to: CGPoint(x: 180, y: 723), width: 16, color: NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.82, alpha: 1))
drawLine(from: CGPoint(x: 143, y: 760), to: CGPoint(x: 180, y: 723), width: 16, color: NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.82, alpha: 1))

let codeY: [CGFloat] = [742, 676, 610, 544, 478, 412]
let codeColors: [(NSColor, NSColor)] = [
    (NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.2, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.83, blue: 0.82, alpha: 1)),
    (NSColor(calibratedRed: 0.34, green: 0.9, blue: 0.48, alpha: 1), NSColor(calibratedRed: 0.15, green: 0.68, blue: 0.94, alpha: 1)),
    (NSColor(calibratedRed: 0.18, green: 0.56, blue: 1.0, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.83, blue: 0.82, alpha: 1)),
    (NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.2, alpha: 1), NSColor(calibratedRed: 0.18, green: 0.83, blue: 0.82, alpha: 1)),
    (NSColor(calibratedRed: 0.18, green: 0.56, blue: 1.0, alpha: 1), NSColor(calibratedRed: 0.34, green: 0.9, blue: 0.48, alpha: 1)),
    (NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.2, alpha: 1), NSColor(calibratedRed: 0.15, green: 0.68, blue: 0.94, alpha: 1))
]

for (index, y) in codeY.enumerated() {
    let (accent, lineColor) = codeColors[index]
    if index > 0 {
        drawDot(center: CGPoint(x: 314, y: y), radius: 10, color: accent)
    }
    drawLine(from: CGPoint(x: 205, y: y), to: CGPoint(x: 360, y: y), width: 20, color: accent)
    drawLine(from: CGPoint(x: 398, y: y), to: CGPoint(x: 532, y: y), width: 20, color: lineColor, alpha: 0.95)
}

let shell = NSBezierPath()
shell.move(to: CGPoint(x: 698, y: 742))
shell.curve(to: CGPoint(x: 900, y: 660), controlPoint1: CGPoint(x: 835, y: 772), controlPoint2: CGPoint(x: 905, y: 733))
shell.curve(to: CGPoint(x: 878, y: 362), controlPoint1: CGPoint(x: 904, y: 535), controlPoint2: CGPoint(x: 918, y: 420))
shell.curve(to: CGPoint(x: 752, y: 210), controlPoint1: CGPoint(x: 850, y: 293), controlPoint2: CGPoint(x: 808, y: 232))
shell.curve(to: CGPoint(x: 650, y: 288), controlPoint1: CGPoint(x: 708, y: 212), controlPoint2: CGPoint(x: 668, y: 238))
shell.curve(to: CGPoint(x: 716, y: 465), controlPoint1: CGPoint(x: 664, y: 344), controlPoint2: CGPoint(x: 676, y: 408))
shell.curve(to: CGPoint(x: 698, y: 742), controlPoint1: CGPoint(x: 768, y: 568), controlPoint2: CGPoint(x: 772, y: 706))
shell.close()

withShadow(color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.3), blur: 30, offset: CGSize(width: 0, height: -16)) {
    fill(shell, with: [
        NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.2, alpha: 1)
    ], angle: -60)
}

let shellRim = NSBezierPath()
shellRim.move(to: CGPoint(x: 770, y: 774))
shellRim.curve(to: CGPoint(x: 917, y: 666), controlPoint1: CGPoint(x: 892, y: 780), controlPoint2: CGPoint(x: 926, y: 739))
shellRim.curve(to: CGPoint(x: 914, y: 386), controlPoint1: CGPoint(x: 904, y: 572), controlPoint2: CGPoint(x: 933, y: 468))
stroke(shellRim, color: NSColor(calibratedRed: 1.0, green: 0.69, blue: 0.1, alpha: 1), width: 18)

let visor = capsulePath(rect(462, 494, 398, 244))
withShadow(color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.35), blur: 34, offset: CGSize(width: 0, height: -18)) {
    fill(visor, with: [
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.14, alpha: 1)
    ], angle: -22)
}
stroke(visor, color: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.93, alpha: 1), width: 14)

let visorHighlight = NSBezierPath()
visorHighlight.move(to: CGPoint(x: 478, y: 616))
visorHighlight.curve(to: CGPoint(x: 532, y: 710), controlPoint1: CGPoint(x: 470, y: 672), controlPoint2: CGPoint(x: 492, y: 708))
stroke(visorHighlight, color: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.9), width: 18)

let eyeLeft = NSBezierPath(ovalIn: rect(518, 546, 72, 120))
let eyeRight = NSBezierPath(ovalIn: rect(640, 544, 88, 128))
withShadow(color: NSColor(calibratedRed: 0.1, green: 0.92, blue: 1, alpha: 0.45), blur: 30) {
    fill(eyeLeft, with: [
        NSColor(calibratedRed: 0.2, green: 0.88, blue: 0.94, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.76, blue: 1.0, alpha: 1)
    ], angle: -90)
    fill(eyeRight, with: [
        NSColor(calibratedRed: 0.2, green: 0.88, blue: 0.94, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.76, blue: 1.0, alpha: 1)
    ], angle: -90)
}

let antennaColor = NSColor(calibratedRed: 0.14, green: 0.45, blue: 1.0, alpha: 1)
drawLine(from: CGPoint(x: 600, y: 742), to: CGPoint(x: 560, y: 826), width: 16, color: antennaColor)
drawLine(from: CGPoint(x: 732, y: 744), to: CGPoint(x: 772, y: 872), width: 16, color: antennaColor)
drawDot(center: CGPoint(x: 545, y: 844), radius: 30, color: NSColor(calibratedRed: 0.15, green: 0.86, blue: 0.97, alpha: 1))
drawDot(center: CGPoint(x: 786, y: 888), radius: 32, color: NSColor(calibratedRed: 0.15, green: 0.86, blue: 0.97, alpha: 1))

let lensFrame = NSBezierPath(ovalIn: rect(418, 392, 176, 176))
withShadow(color: NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.18, alpha: 0.45), blur: 24, offset: CGSize(width: 0, height: -10)) {
    fill(lensFrame, with: [
        NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.72, blue: 0.92, alpha: 1)
    ], angle: -120)
}

let lens = NSBezierPath(ovalIn: rect(444, 418, 124, 124))
fill(lens, with: [
    NSColor(calibratedRed: 0.12, green: 0.72, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.82, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.2, blue: 0.56, alpha: 1)
], angle: -90)

let lensSpark = NSBezierPath()
lensSpark.move(to: CGPoint(x: 470, y: 510))
lensSpark.curve(to: CGPoint(x: 500, y: 550), controlPoint1: CGPoint(x: 468, y: 530), controlPoint2: CGPoint(x: 482, y: 548))
stroke(lensSpark, color: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.75), width: 12)

drawLine(from: CGPoint(x: 548, y: 410), to: CGPoint(x: 690, y: 286), width: 30, color: NSColor(calibratedRed: 0.25, green: 0.49, blue: 0.91, alpha: 1))
drawLine(from: CGPoint(x: 556, y: 396), to: CGPoint(x: 698, y: 272), width: 10, color: NSColor(calibratedRed: 0.78, green: 0.89, blue: 1.0, alpha: 0.5))

for (index, alpha) in [0.9, 0.65, 0.42].enumerated() {
    let baseY = CGFloat(250 - (index * 34))
    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: 760, y: baseY + 50), radius: CGFloat(84 + index * 24), startAngle: 220, endAngle: 334)
    stroke(arc, color: NSColor(calibratedRed: 0.11, green: 0.43, blue: 1.0, alpha: alpha), width: 16 - CGFloat(index * 2))
}

let lowerGlow = roundedPath(rect(350, 140, 250, 18), radius: 9)
fill(lowerGlow, with: [
    NSColor(calibratedRed: 0.1, green: 0.5, blue: 1.0, alpha: 0),
    NSColor(calibratedRed: 0.1, green: 0.5, blue: 1.0, alpha: 0.75),
    NSColor(calibratedRed: 0.1, green: 0.5, blue: 1.0, alpha: 0)
], angle: 0)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Could not encode PNG")
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote icon source to \(outputPath)")
