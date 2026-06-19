#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count >= 4 else {
    fputs("usage: render_dmg_background.swift <icon-path> <output-path> <app-name>\n", stderr)
    exit(64)
}

let iconPath = arguments[1]
let outputPath = arguments[2]
let appName = arguments[3]

let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)

func drawText(_ text: String, at point: NSPoint, attributes: [NSAttributedString.Key: Any]) {
    NSString(string: text).draw(at: point, withAttributes: attributes)
}

func centeredTextOrigin(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSPoint {
    let measured = NSString(string: text).size(withAttributes: attributes)
    return NSPoint(x: (size.width - measured.width) / 2, y: y)
}

func centeredTextOrigin(_ text: String, midX: CGFloat, y: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSPoint {
    let measured = NSString(string: text).size(withAttributes: attributes)
    return NSPoint(x: midX - measured.width / 2, y: y)
}

func drawArrow(from start: NSPoint, to end: NSPoint) {
    let stroke = NSColor(calibratedRed: 0.06, green: 0.47, blue: 0.44, alpha: 0.82)
    stroke.setStroke()

    let path = NSBezierPath()
    path.lineWidth = 4
    path.lineCapStyle = .round
    path.move(to: start)
    path.line(to: end)
    path.stroke()

    let head = NSBezierPath()
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: end.x - 20, y: end.y + 15))
    head.line(to: end)
    head.line(to: NSPoint(x: end.x - 20, y: end.y - 15))
    head.stroke()
}

image.lockFocus()

NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.95, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let topWash = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.99, green: 1.0, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.93, alpha: 1)
    ]
)
topWash?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.13, alpha: 1)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.27, green: 0.32, blue: 0.33, alpha: 1)
]
drawText("Install \(appName)", at: centeredTextOrigin("Install \(appName)", y: 358, attributes: titleAttributes), attributes: titleAttributes)

let subtitle = "Drag \(appName) into Applications to finish setup."
drawText(subtitle, at: centeredTextOrigin(subtitle, y: 333, attributes: subtitleAttributes), attributes: subtitleAttributes)

let iconRect = NSRect(x: 118, y: 159, width: 150, height: 150)
let applicationsRect = NSRect(x: 457, y: 159, width: 150, height: 150)

drawArrow(from: NSPoint(x: iconRect.maxX + 48, y: iconRect.midY), to: NSPoint(x: applicationsRect.minX - 48, y: applicationsRect.midY))

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render installer background\n", stderr)
    exit(1)
}

do {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData.write(to: outputURL)
} catch {
    fputs("failed to write installer background: \(error)\n", stderr)
    exit(1)
}
