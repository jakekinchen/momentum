import AppKit
import CamiFitEngine
import Combine
import Foundation
import SwiftUI

struct LiveWorkerPythonCommand: Equatable {
    let executableURL: URL
    let argumentsPrefix: [String]

    var displayName: String {
        ([executableURL.path] + argumentsPrefix).joined(separator: " ")
    }
}

enum LiveWorkerPaths {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> (python: LiveWorkerPythonCommand, script: URL, model: URL) {
        func expand(_ path: String) -> URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let repo = environment["CAMIFIT_REPO_ROOT"].map(expand) ?? defaultRepoRoot()
        return (
            resolvePython(environment: environment, repo: repo, fileManager: fileManager),
            repo.appendingPathComponent("pose_worker/pose_worker.py"),
            repo.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        )
    }

    private static func resolvePython(
        environment: [String: String],
        repo: URL,
        fileManager: FileManager
    ) -> LiveWorkerPythonCommand {
        if let configured = environment["CAMIFIT_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return pythonCommand(for: configured)
        }

        let candidates = pythonCandidates(repo: repo, home: fileManager.homeDirectoryForCurrentUser)
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return LiveWorkerPythonCommand(executableURL: candidate, argumentsPrefix: [])
        }
        return pythonCommand(for: "python3")
    }

    static func pythonCandidates(repo: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            repo.appendingPathComponent(".venv/bin/python"),
            home.appendingPathComponent(".local/bin/python3.12"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3.12"),
            URL(fileURLWithPath: "/usr/local/bin/python3.12"),
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3")
        ]
    }

    private static func defaultRepoRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func pythonCommand(for configured: String) -> LiveWorkerPythonCommand {
        let expanded = (configured as NSString).expandingTildeInPath
        let looksLikePath = expanded.contains("/") || expanded.hasPrefix(".")
        if looksLikePath {
            return LiveWorkerPythonCommand(
                executableURL: URL(fileURLWithPath: expanded),
                argumentsPrefix: []
            )
        }

        // macOS no longer guarantees a `python` shim. Treat that override as
        // intent to use Python 3 so Live Camera fails at health-check time with
        // actionable MediaPipe/model setup diagnostics, not at process launch.
        let command = configured == "python" ? "python3" : configured
        return LiveWorkerPythonCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            argumentsPrefix: [command]
        )
    }
}

/// Owns the live pipeline: camera → persistent pose worker → engine. Kept as an ObservableObject
/// so the camera frame callback captures a stable reference (not a SwiftUI value-type View).
final class LiveSession: ObservableObject {
    @Published var running = false
    @Published var isLiveCamera = false
    @Published var errorText: String?
    @Published var sourceSize: CGSize = .zero
    @Published var recording = false
    @Published var availableCameras: [CameraDevice] = []
    @Published var selectedCameraID: String?
    @Published var poseReadiness: PosePipelineReadiness = .idle
    @Published var cameraSettingsPromptID: UUID?
    let recordDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/camifit/dist/capture")

    let camera = LiveCameraController()
    private var worker: LivePoseWorkerClient?
    private weak var viewModel: AppExerciseSessionViewModel?
    private var onPoseFrame: ((PoseFrame) -> Void)?
    private var cameraReadinessCancellable: AnyCancellable?
    private var syntheticTimer: Timer?
    private var syntheticFrames: [PoseFrame] = []
    private var syntheticIndex = 0
    private let shotDir = ProcessInfo.processInfo.environment["CAMIFIT_SHOT_DIR"]
    private var shotCounter = 0

    var routesPoseFramesExternally: Bool {
        onPoseFrame != nil
    }

    /// Renders the current overlay + HUD to a PNG via ImageRenderer (no screen-recording
    /// permission needed) when CAMIFIT_SHOT_DIR is set — for deterministic GUI captures.
    init() {
        cameraReadinessCancellable = camera.$readiness.sink { [weak self] readiness in
            DispatchQueue.main.async {
                self?.handleCameraReadiness(readiness)
            }
        }
    }

    /// Renders the current overlay + HUD to a PNG via ImageRenderer (no screen-recording
    /// permission needed) when CAMIFIT_SHOT_DIR is set — for deterministic GUI captures.
    private func captureSnapshotIfNeeded() {
        guard let shotDir, let viewModel, syntheticIndex % 3 == 0 else { return }
        let snapshot = CamiFitFrameSnapshot(
            overlay: viewModel.latestPoseOverlayState,
            exercise: viewModel.state.selectedExerciseName ?? "Squat",
            reps: viewModel.state.repCount,
            cue: viewModel.state.cueText
        )
        let index = shotCounter
        shotCounter += 1
        Task { @MainActor in
            let renderer = ImageRenderer(content: snapshot)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return }
            let url = URL(fileURLWithPath: shotDir).appendingPathComponent(String(format: "frame_%04d.png", index))
            try? data.write(to: url)
        }
    }

    /// Plays a recorded landmark trace frame-by-frame into the engine (no camera) so the GUI
    /// can be exercised + screenshotted deterministically from synthetic data.
    func startSynthetic(viewModel: AppExerciseSessionViewModel, framesURL: URL) {
        self.viewModel = viewModel
        onPoseFrame = nil
        // Synthetic trace is a squat; prefer the squat preset (CAMIFIT_SYNTHETIC_EXERCISE overrides).
        let preferredID = ProcessInfo.processInfo.environment["CAMIFIT_SYNTHETIC_EXERCISE"] ?? "bodyweight_squat"
        let preset = viewModel.availablePresets.first { $0.id == preferredID } ?? viewModel.availablePresets.first
        if let preset {
            try? viewModel.selectPreset(id: preset.id)
        }
        viewModel.resetLiveSession()
        do {
            syntheticFrames = try MediaPipePoseJSONLDecoder.decode(contentsOf: framesURL)
        } catch {
            errorText = "Synthetic trace failed to load: \(error.localizedDescription)"
            return
        }
        guard !syntheticFrames.isEmpty else {
            errorText = "Synthetic trace had no frames"
            return
        }
        syntheticIndex = 0
        if let shotDir { try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true) }
        errorText = nil
        poseReadiness = .ready
        running = true
        isLiveCamera = false
        syntheticTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.syntheticIndex >= self.syntheticFrames.count {
                self.viewModel?.resetLiveSession()   // loop the trace for continuous animation
                self.syntheticIndex = 0
                return
            }
            self.viewModel?.ingestLiveFrame(self.syntheticFrames[self.syntheticIndex])
            self.captureSnapshotIfNeeded()
            self.syntheticIndex += 1
        }
    }

    func start(
        viewModel: AppExerciseSessionViewModel,
        onPoseFrame: ((PoseFrame) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onPoseFrame = onPoseFrame
        if viewModel.state.selectedExerciseID == nil, let first = viewModel.availablePresets.first {
            try? viewModel.selectPreset(id: first.id)
        }
        viewModel.resetLiveSession()

        let paths = LiveWorkerPaths.resolve()
        let client = LivePoseWorkerClient(python: paths.python, scriptURL: paths.script, modelURL: paths.model)
        poseReadiness = .workerStarting
        do {
            try client.start()
        } catch {
            errorText = [
                "Pose worker failed to start: \(error.localizedDescription)",
                "Python: \(paths.python.displayName)",
                "Worker: \(paths.script.path)",
                "Model: \(paths.model.path)"
            ].joined(separator: "\n")
            poseReadiness = .failed(errorText ?? "Pose worker failed")
            return
        }
        worker = client
        errorText = nil

        camera.onFrame = { [weak self] path, timestampMS, size in
            guard let self, let worker = self.worker else { return }
            DispatchQueue.main.async { self.sourceSize = size }
            do {
                if let frame = try worker.predict(imagePath: path, frameID: Int(truncatingIfNeeded: timestampMS), timestampMS: timestampMS) {
                    DispatchQueue.main.async {
                        self.poseReadiness = .ready
                        if let onPoseFrame = self.onPoseFrame {
                            onPoseFrame(frame)
                        } else {
                            self.viewModel?.ingestLiveFrame(frame)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        if self.poseReadiness != .ready {
                            self.poseReadiness = .waitingForFirstPose
                        }
                    }
                }
            } catch {
                // transient per-frame error — drop this frame, keep going.
                DispatchQueue.main.async {
                    self.poseReadiness = .degraded("Dropping a camera frame")
                }
            }
        }
        camera.preferredDeviceID = selectedCameraID
        camera.start()
        running = true
        isLiveCamera = true
    }

    func refreshCameras() {
        availableCameras = LiveCameraController.discoverCameras()
    }

    func requestCameraSettingsIfNoCameras() {
        refreshCameras()
        guard availableCameras.isEmpty else { return }
        cameraSettingsPromptID = UUID()
    }

    func stop() {
        syntheticTimer?.invalidate()
        syntheticTimer = nil
        camera.stop()
        camera.onFrame = nil
        onPoseFrame = nil
        camera.recording = false
        recording = false
        worker?.stop()
        worker = nil
        running = false
        isLiveCamera = false
        poseReadiness = .idle
    }

    /// Starts/stops capturing the live camera frames to `recordDir` (for offline analysis).
    func toggleRecording() {
        if recording {
            camera.recording = false
            recording = false
        } else {
            try? FileManager.default.removeItem(at: recordDir)
            try? FileManager.default.createDirectory(at: recordDir, withIntermediateDirectories: true)
            camera.recordDir = recordDir
            camera.recording = true
            recording = true
        }
    }

    private func handleCameraReadiness(_ readiness: CameraReadiness) {
        switch readiness {
        case .noDevice:
            errorText = nil
            refreshCameras()
            cameraSettingsPromptID = UUID()
            if running, isLiveCamera {
                poseReadiness = .camera(readiness)
            }
        case .streaming:
            if running, isLiveCamera, poseReadiness != .ready {
                poseReadiness = .waitingForFirstPose
            }
        default:
            if running, isLiveCamera {
                poseReadiness = .camera(readiness)
            }
        }
    }
}

/// Camera-free verification surface: auto-plays a synthetic landmark trace through the real
/// engine so the skeleton animates + reps count, for deterministic screenshots.
struct SyntheticDemoView: View {
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    let framesURL: URL
    @StateObject private var session = LiveSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Future Coach - Synthetic Demo").font(.headline)
                Spacer()
                Text("synthetic squat trace").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)

            ZStack {
                LinearGradient(colors: [Color(white: 0.10), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
                PoseOverlayView(state: viewModel.latestPoseOverlayState)
                    .allowsHitTesting(false)
                VStack {
                    hud
                    Spacer()
                    if let errorText = session.errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 10)
                    }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            viewModel.loadAvailablePresets()
            session.startSynthetic(viewModel: viewModel, framesURL: framesURL)
        }
        .onDisappear { session.stop() }
    }

    private var hud: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text((viewModel.state.selectedExerciseName ?? "Squat").uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                if let cue = viewModel.state.cueText {
                    Text(cue).font(.headline).foregroundStyle(.white)
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 0) {
                Text("\(viewModel.state.repCount)")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("REPS").font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .frame(maxWidth: 420)
    }
}

/// A fixed-size, self-contained render of the live overlay + rep HUD, used by ImageRenderer
/// to produce deterministic PNG snapshots of the actual SwiftUI surface (no screen capture).
struct CamiFitFrameSnapshot: View {
    let overlay: AppPoseOverlayState
    let exercise: String
    let reps: Int
    let cue: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.10), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
            PoseOverlayView(state: overlay)
            VStack {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.uppercased()).font(.caption.bold()).foregroundStyle(.cyan)
                        if let cue { Text(cue).font(.headline).foregroundStyle(.white) }
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 0) {
                        Text("\(reps)").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                        Text("REPS").font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                .frame(maxWidth: 420)
                .padding(.top, 16)
                Spacer()
            }
        }
        .frame(width: 760, height: 600)
    }
}

/// Pose overlay that maps normalized landmarks through the SAME resizeAspectFill transform the
/// camera preview uses, so the skeleton aligns with the body on screen (not stretched to the view).
struct LivePoseOverlay: View {
    let state: AppPoseOverlayState
    let sourceSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let vw = proxy.size.width, vh = proxy.size.height
            let sw = sourceSize.width > 0 ? sourceSize.width : vw
            let sh = sourceSize.height > 0 ? sourceSize.height : vh
            let scale = max(vw / sw, vh / sh)          // aspect-fill: cover the view
            let dw = sw * scale, dh = sh * scale
            let ox = (vw - dw) / 2, oy = (vh - dh) / 2  // centered crop, matches AVLayerVideoGravity.resizeAspectFill
            let byID = Dictionary(uniqueKeysWithValues: state.points.map { ($0.id, $0) })
            Canvas { ctx, _ in
                for seg in state.segments {
                    guard let a = byID[seg.fromID], let b = byID[seg.toID] else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: a.x * dw + ox, y: a.y * dh + oy))
                    path.addLine(to: CGPoint(x: b.x * dw + ox, y: b.y * dh + oy))
                    ctx.stroke(path, with: .color(.cyan), lineWidth: 3)
                }
                for p in state.points {
                    let x = p.x * dw + ox, y = p.y * dh + oy
                    let r = 4.0 + p.confidence * 2.0
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.yellow))
                }
            }
        }
    }
}
