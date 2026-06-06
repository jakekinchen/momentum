import AVFoundation
import CoreImage
import Foundation
import SwiftUI

/// A selectable camera input (built-in, external, or Continuity Camera).
struct CameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Captures webcam frames, throttles + downscales them to JPEG files on disk, and hands each
/// frame path to `onFrame`. Also vends an `AVCaptureVideoPreviewLayer` for live preview.
final class LiveCameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var readiness: CameraReadiness = .idle
    @Published private(set) var statusText = CameraReadiness.idle.displayText

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camifit.live-camera.session")
    private let sampleQueue = DispatchQueue(label: "camifit.live-camera.frames")
    private let ciContext = CIContext()
    private let frameDir: URL
    private var lastEmit = Date.distantPast
    private let minInterval: TimeInterval = 0.08      // ~12 fps to the worker
    private let maxDimension: CGFloat = 640
    private var frameCounter = 0
    private let diagDir = ProcessInfo.processInfo.environment["CAMIFIT_FRAME_DIR"]
    var recordDir: URL?
    var recording = false
    /// nil = use the system default camera.
    var preferredDeviceID: String?

    /// (imagePath, timestampMS, sourceSize)
    var onFrame: ((String, Int64, CGSize) -> Void)?

    override init() {
        frameDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("camifit-live-frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)
        super.init()
        if let diagDir { try? FileManager.default.createDirectory(atPath: diagDir, withIntermediateDirectories: true) }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.setReadiness(.starting) }
            self.sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            DispatchQueue.main.async { self.setReadiness(.requestingPermission) }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    DispatchQueue.main.async { self.setReadiness(.denied) }
                    return
                }
                DispatchQueue.main.async { self.setReadiness(.starting) }
                self.sessionQueue.async { self.configureAndRun() }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.setReadiness(.denied) }
        @unknown default:
            DispatchQueue.main.async { self.setReadiness(.failed("Camera unavailable")) }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.setReadiness(.idle) }
        }
    }

    /// Enumerates selectable video cameras (built-in, external, Continuity).
    static func discoverCameras() -> [CameraDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        return discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Swaps the active camera input while running (takes effect on next start if idle).
    func setDevice(_ id: String?) {
        preferredDeviceID = id
        sessionQueue.async {
            guard self.session.isRunning,
                  let device = self.resolveDevice(),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for existing in self.session.inputs { self.session.removeInput(existing) }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            self.session.commitConfiguration()
        }
    }

    private func resolveDevice() -> AVCaptureDevice? {
        if let preferredDeviceID, let device = AVCaptureDevice(uniqueID: preferredDeviceID) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configureAndRun() {
        if session.isRunning { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        for input in session.inputs { session.removeInput(input) }
        for out in session.outputs { session.removeOutput(out) }

        guard let device = resolveDevice(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.setReadiness(.noDevice) }
            return
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.setReadiness(.streaming(.zero)) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= minInterval else { return }
        lastEmit = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let scale = min(1, maxDimension / CGFloat(max(width, height)))
        let image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }

        frameCounter += 1
        let url = frameDir.appendingPathComponent("frame-\(Int(now.timeIntervalSince1970 * 1000)).jpg")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality as String: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }

        let tsMS = Int64(now.timeIntervalSince1970 * 1000)
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        DispatchQueue.main.async { self.setReadiness(.streaming(size)) }
        onFrame?(url.path, tsMS, size)
        if let diagDir {
            try? FileManager.default.copyItem(atPath: url.path, toPath: (diagDir as NSString).appendingPathComponent("live_\(tsMS).jpg"))
        }
        if recording, let recordDir {
            try? FileManager.default.copyItem(atPath: url.path, toPath: recordDir.appendingPathComponent("rec_\(tsMS).jpg").path)
        }
        cleanupOldFrames()
    }

    private func cleanupOldFrames() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: frameDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted {
            let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for file in sorted.dropFirst(12) { try? FileManager.default.removeItem(at: file) }
    }

    private func setReadiness(_ readiness: CameraReadiness) {
        self.readiness = readiness
        statusText = readiness.displayText
    }
}

import CoreGraphics
import ImageIO

/// Live `AVCaptureVideoPreviewLayer` host.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let preview = nsView.layer as? AVCaptureVideoPreviewLayer {
            preview.frame = nsView.bounds
        }
    }
}
