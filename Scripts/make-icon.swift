#!/usr/bin/env swift
// Generates Assets/icon_1024.png — a stylized gauge for the TokenMeter app icon.
// Run: swift Scripts/make-icon.swift
import AppKit

let outDir = URL(fileURLWithPath: "Assets")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let out = outDir.appendingPathComponent("icon_1024.png")

let S: Int = 1024
let sF = CGFloat(S)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)
else {
    fputs("could not create bitmap\n", stderr); exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-rect background with a warm gradient (orange→magenta).
let bgRect = NSRect(x: 0, y: 0, width: sF, height: sF)
let cornerRadius: CGFloat = sF * 0.22
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSGraphicsContext.current?.cgContext.saveGState()
bgPath.addClip()

let gradient = NSGradient(
    colorsAndLocations:
        (NSColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1.0), 0.0),
        (NSColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1.0), 0.55),
        (NSColor(red: 0.55, green: 0.20, blue: 0.65, alpha: 1.0), 1.0)
)!
gradient.draw(in: bgRect, angle: 135)

// Outer dial ring.
let center = NSPoint(x: sF / 2, y: sF * 0.50)
let dialRadius = sF * 0.32
NSColor.white.withAlphaComponent(0.95).setStroke()
let dial = NSBezierPath()
dial.lineWidth = sF * 0.045
dial.lineCapStyle = .round
dial.appendArc(withCenter: center, radius: dialRadius,
               startAngle: 210, endAngle: -30, clockwise: false)
dial.stroke()

// Tick marks every 30°.
for deg in stride(from: 210.0, through: 330.0 + 360.0, by: 30.0) {
    let real = deg.truncatingRemainder(dividingBy: 360)
    let rad = real * .pi / 180
    let r1 = dialRadius - sF * 0.005
    let r2 = dialRadius - sF * 0.055
    let p1 = NSPoint(x: center.x + cos(rad) * r1, y: center.y + sin(rad) * r1)
    let p2 = NSPoint(x: center.x + cos(rad) * r2, y: center.y + sin(rad) * r2)
    let tick = NSBezierPath()
    tick.lineWidth = sF * 0.015
    tick.lineCapStyle = .round
    tick.move(to: p1)
    tick.line(to: p2)
    tick.stroke()
}

// Needle pointing at ~70%.
let needleAngle: CGFloat = 35 * .pi / 180
let needleTip = NSPoint(
    x: center.x + cos(needleAngle) * (dialRadius - sF * 0.02),
    y: center.y + sin(needleAngle) * (dialRadius - sF * 0.02)
)
let needle = NSBezierPath()
needle.lineWidth = sF * 0.038
needle.lineCapStyle = .round
needle.move(to: center)
needle.line(to: needleTip)
needle.stroke()

// Center hub.
NSColor.white.setFill()
let hub = NSBezierPath(ovalIn: NSRect(
    x: center.x - sF * 0.045, y: center.y - sF * 0.045,
    width: sF * 0.09, height: sF * 0.09))
hub.fill()

// "T" wordmark.
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: sF * 0.18, weight: .heavy),
    .foregroundColor: NSColor.white.withAlphaComponent(0.95)
]
let str = NSAttributedString(string: "T", attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(x: (sF - strSize.width) / 2, y: sF * 0.08))

NSGraphicsContext.current?.cgContext.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("png encoding failed\n", stderr); exit(1)
}
try png.write(to: out)
print("✓ wrote \(out.path)")
