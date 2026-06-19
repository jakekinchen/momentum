#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXPERIMENT_DIR="$ROOT_DIR/website/experiments/onboarding-video"
PUBLIC_DIR="$ROOT_DIR/website/public/app-assets/onboarding"

WIDTH="${WIDTH:-640}"
HEIGHT="${HEIGHT:-272}"
FPS="${FPS:-20}"
DURATION_SECONDS="${DURATION_SECONDS:-21.15}"

SOURCE_ONBOARDING="$ROOT_DIR/Sources/CamiFitApp/OnboardingView.swift"
SOURCE_BRAND="$ROOT_DIR/Sources/CamiFitApp/BrandLogoMark.swift"
SOURCE_BRAND_ASSET="$ROOT_DIR/Sources/CamiFitApp/Resources/Brand/future.svg"

for required in "$SOURCE_ONBOARDING" "$SOURCE_BRAND" "$SOURCE_BRAND_ASSET"; do
  if [[ ! -e "$required" ]]; then
    echo "missing required source: $required" >&2
    exit 1
  fi
done

CAPTURE_ROOT="$(mktemp -d "$EXPERIMENT_DIR/.capture.XXXXXX")"
PACKAGE_DIR="$CAPTURE_ROOT/package"
FRAMES_DIR="$CAPTURE_ROOT/frames"

cleanup() {
  if [[ "${KEEP_CAPTURE_TMP:-0}" != "1" ]]; then
    rm -rf "$CAPTURE_ROOT"
  else
    echo "kept capture temp directory: $CAPTURE_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p \
  "$PACKAGE_DIR/Sources/OnboardingCapture/Resources/Brand" \
  "$FRAMES_DIR" \
  "$PUBLIC_DIR"

cat >"$PACKAGE_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CamiFitOnboardingCapture",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "OnboardingCapture", targets: ["OnboardingCapture"])
    ],
    targets: [
        .executableTarget(
            name: "OnboardingCapture",
            resources: [
                .copy("Resources/Brand")
            ]
        )
    ]
)
SWIFT

cp "$SOURCE_BRAND" "$PACKAGE_DIR/Sources/OnboardingCapture/BrandLogoMark.swift"
cp "$SOURCE_BRAND_ASSET" "$PACKAGE_DIR/Sources/OnboardingCapture/Resources/Brand/future.svg"

{
  echo "import AppKit"
  echo "import ImageIO"
  echo "import UniformTypeIdentifiers"
  cat "$SOURCE_ONBOARDING"
  cat <<'SWIFT'

@MainActor
private final class OnboardingCaptureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var frameIndex = 1

    private let outputDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMIFIT_ONBOARDING_CAPTURE_DIR"]!)
    private let width = Int(ProcessInfo.processInfo.environment["CAMIFIT_ONBOARDING_CAPTURE_WIDTH"] ?? "640") ?? 640
    private let height = Int(ProcessInfo.processInfo.environment["CAMIFIT_ONBOARDING_CAPTURE_HEIGHT"] ?? "272") ?? 272
    private let fps = Double(ProcessInfo.processInfo.environment["CAMIFIT_ONBOARDING_CAPTURE_FPS"] ?? "20") ?? 20
    private let duration = Double(ProcessInfo.processInfo.environment["CAMIFIT_ONBOARDING_CAPTURE_DURATION"] ?? "21.15") ?? 21.15

    private var totalFrames: Int {
        max(1, Int((duration * fps).rounded(.up)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let contentSize = NSSize(width: width, height: height)
        let rootView = OnboardingFeatureVisual(stepID: .movement)
            .frame(width: contentSize.width, height: contentSize.height)

        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        hostingView.wantsLayer = true
        self.hostingView = hostingView

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: width, height: height)
        let origin = NSPoint(
            x: screenFrame.minX + 80,
            y: screenFrame.maxY - contentSize.height - 80
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.contentView = hostingView
        window.orderFrontRegardless()
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.captureNextFrame()
        }
    }

    private func captureNextFrame() {
        guard frameIndex <= totalFrames else {
            NSApp.terminate(nil)
            return
        }

        hostingView?.needsDisplay = true
        hostingView?.displayIfNeeded()

        guard let cgImage = captureHostingViewImage() else {
            fputs("failed to capture frame \(frameIndex)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        do {
            try writePNG(cgImage, to: outputDirectory.appendingPathComponent(String(format: "frame_%04d.png", frameIndex)))
        } catch {
            fputs("failed to write frame \(frameIndex): \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        frameIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / fps)) {
            self.captureNextFrame()
        }
    }

    private func captureHostingViewImage() -> CGImage? {
        guard let hostingView else { return nil }
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.cgImage
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@main
private enum OnboardingCaptureApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = OnboardingCaptureDelegate()
        app.delegate = delegate
        app.run()
    }
}
SWIFT
} >"$PACKAGE_DIR/Sources/OnboardingCapture/CapturedOnboardingView.swift"

(
  cd "$PACKAGE_DIR"
  CAMIFIT_ONBOARDING_CAPTURE_DIR="$FRAMES_DIR" \
  CAMIFIT_ONBOARDING_CAPTURE_WIDTH="$WIDTH" \
  CAMIFIT_ONBOARDING_CAPTURE_HEIGHT="$HEIGHT" \
  CAMIFIT_ONBOARDING_CAPTURE_FPS="$FPS" \
  CAMIFIT_ONBOARDING_CAPTURE_DURATION="$DURATION_SECONDS" \
    swift run -c release OnboardingCapture
)

POSTER="$PUBLIC_DIR/movement-tracking-swiftui-poster.jpg"
MP4="$PUBLIC_DIR/movement-tracking-swiftui.mp4"
WEBM="$PUBLIC_DIR/movement-tracking-swiftui.webm"

ffmpeg -hide_banner -loglevel error -y \
  -i "$FRAMES_DIR/frame_0001.png" \
  -frames:v 1 \
  -q:v 4 \
  "$POSTER"

ffmpeg -hide_banner -loglevel error -y \
  -framerate "$FPS" \
  -i "$FRAMES_DIR/frame_%04d.png" \
  -vf "format=yuv420p" \
  -an \
  -c:v libx264 \
  -preset veryslow \
  -crf 24 \
  -movflags +faststart \
  "$MP4"

ffmpeg -hide_banner -loglevel error -y \
  -framerate "$FPS" \
  -i "$FRAMES_DIR/frame_%04d.png" \
  -an \
  -c:v libvpx-vp9 \
  -b:v 0 \
  -crf 34 \
  "$WEBM"

echo "Rendered from SwiftUI source:"
echo "  $SOURCE_ONBOARDING"
echo "Outputs:"
du -h "$POSTER" "$MP4" "$WEBM"
