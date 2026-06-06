import AppKit
import Foundation

private struct IconSpec {
    let filename: String
    let pixels: Int
}

private let specs = [
    IconSpec(filename: "icon_16x16.png", pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixels: 32),
    IconSpec(filename: "icon_32x32.png", pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixels: 64),
    IconSpec(filename: "icon_128x128.png", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixels: 256),
    IconSpec(filename: "icon_256x256.png", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixels: 512),
    IconSpec(filename: "icon_512x512.png", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixels: 1024)
]

private enum IconGeneratorError: Error, CustomStringConvertible {
    case missingArgument(String)
    case missingBrandSVG(URL)
    case couldNotLoadBrandSVG(URL)
    case couldNotRenderPNG(String)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case let .missingArgument(flag):
            return "Missing required argument \(flag)."
        case let .missingBrandSVG(url):
            return "Future logo SVG not found at \(url.path)."
        case let .couldNotLoadBrandSVG(url):
            return "Could not load Future logo SVG at \(url.path)."
        case let .couldNotRenderPNG(name):
            return "Could not render \(name)."
        case let .iconutilFailed(status):
            return "iconutil failed with status \(status)."
        }
    }
}

private func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func aspectFitRect(aspectRatio size: NSSize, inside bounds: NSRect) -> NSRect {
    guard size.width > 0, size.height > 0 else { return bounds }

    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let fittedSize = NSSize(width: size.width * scale, height: size.height * scale)
    return NSRect(
        x: bounds.midX - fittedSize.width / 2,
        y: bounds.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height
    )
}

private func renderIconPNG(markImage: NSImage, pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    guard let representation = NSBitmapImageRep(
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
    ) else {
        throw IconGeneratorError.couldNotRenderPNG("\(pixels)x\(pixels)")
    }

    representation.size = NSSize(width: size, height: size)

    let previousContext = NSGraphicsContext.current
    let context = NSGraphicsContext(bitmapImageRep: representation)
    context?.cgContext.setShouldAntialias(true)
    context?.cgContext.setAllowsAntialiasing(true)
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    let canvasRect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvasRect.fill()

    let backgroundInset = size * 72 / 1024
    let backgroundRadius = size * 220 / 1024
    let backgroundPath = NSBezierPath(
        roundedRect: canvasRect.insetBy(dx: backgroundInset, dy: backgroundInset),
        xRadius: backgroundRadius,
        yRadius: backgroundRadius
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.045, green: 0.065, blue: 0.085, alpha: 1),
        NSColor(calibratedRed: 0.075, green: 0.135, blue: 0.125, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.040, blue: 0.055, alpha: 1)
    ])?.draw(in: backgroundPath, angle: -36)

    let markRect = aspectFitRect(
        aspectRatio: markImage.size,
        inside: canvasRect.insetBy(dx: size * 300 / 1024, dy: size * 210 / 1024)
    )
    markImage.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1)

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconGeneratorError.couldNotRenderPNG("\(pixels)x\(pixels)")
    }
    return data
}

private func runIconutil(iconsetURL: URL, outputURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", outputURL.path, iconsetURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw IconGeneratorError.iconutilFailed(process.terminationStatus)
    }
}

private func main() throws {
    guard let brandPath = argument(after: "--brand") else {
        throw IconGeneratorError.missingArgument("--brand")
    }
    guard let outputPath = argument(after: "--output") else {
        throw IconGeneratorError.missingArgument("--output")
    }

    let fileManager = FileManager.default
    let brandURL = URL(fileURLWithPath: brandPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    guard fileManager.fileExists(atPath: brandURL.path) else {
        throw IconGeneratorError.missingBrandSVG(brandURL)
    }
    guard let markImage = NSImage(contentsOf: brandURL) else {
        throw IconGeneratorError.couldNotLoadBrandSVG(brandURL)
    }

    let iconsetURL = fileManager.temporaryDirectory
        .appendingPathComponent("FutureCoachAppIcon-\(UUID().uuidString).iconset")
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: iconsetURL) }

    for spec in specs {
        let data = try renderIconPNG(markImage: markImage, pixels: spec.pixels)
        try data.write(to: iconsetURL.appendingPathComponent(spec.filename), options: .atomic)
    }

    try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? fileManager.removeItem(at: outputURL)
    try runIconutil(iconsetURL: iconsetURL, outputURL: outputURL)
}

do {
    try main()
} catch {
    fputs("generate_future_app_icon: \(error)\n", stderr)
    exit(1)
}
