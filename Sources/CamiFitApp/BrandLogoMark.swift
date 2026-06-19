import AppKit
import SwiftUI

enum CamiFitBrandLogo {
    static let markImage: NSImage? = {
        guard let url = AppResourceBundle.url(forResource: "future", withExtension: "svg", subdirectory: "Brand") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static let appIconImage: NSImage? = {
        guard let markImage else { return nil }

        let canvasSize = NSSize(width: 1024, height: 1024)
        let icon = NSImage(size: canvasSize)
        icon.lockFocus()

        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        let backgroundPath = NSBezierPath(roundedRect: canvasRect.insetBy(dx: 72, dy: 72), xRadius: 220, yRadius: 220)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.045, green: 0.065, blue: 0.085, alpha: 1),
            NSColor(calibratedRed: 0.075, green: 0.135, blue: 0.125, alpha: 1),
            NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.055, alpha: 1)
        ])?.draw(in: backgroundPath, angle: -36)

        let markRect = aspectFitRect(aspectRatio: markImage.size, inside: canvasRect.insetBy(dx: 300, dy: 210))
        markImage.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1)

        icon.unlockFocus()
        return icon
    }()

    static func applyAsApplicationIcon() {
        guard let appIconImage else { return }
        NSApplication.shared.applicationIconImage = appIconImage
    }

    private static func aspectFitRect(aspectRatio size: NSSize, inside bounds: NSRect) -> NSRect {
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
}

struct BrandLogoMark: View {
    var body: some View {
        Group {
            if let image = CamiFitBrandLogo.markImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("\(ProductBrand.fullName) logo")
            } else {
                Image(systemName: "figure.strengthtraining.functional")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(ProductBrand.fullName)
            }
        }
    }
}
