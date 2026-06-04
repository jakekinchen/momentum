import CamiFitEngine
import Foundation
import SwiftUI

enum LiveWorkerPaths {
    static func resolve() -> (python: URL, script: URL, model: URL) {
        let env = ProcessInfo.processInfo.environment
        func expand(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        let repo = env["CAMIFIT_REPO_ROOT"].map(expand) ?? expand("~/Developer/camifit")
        let python = env["CAMIFIT_PYTHON"].map(expand) ?? expand("~/Developer/camifit-pose-venv/bin/python")
        return (
            python,
            repo.appendingPathComponent("pose_worker/pose_worker.py"),
            repo.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        )
    }
}

/// Owns the live pipeline: camera → persistent pose worker → engine. Kept as an ObservableObject
/// so the camera frame callback captures a stable reference (not a SwiftUI value-type View).
final class LiveSession: ObservableObject {
    @Published var running = false
    @Published var errorText: String?

    let camera = LiveCameraController()
    private var worker: LivePoseWorkerClient?
    private weak var viewModel: AppExerciseSessionViewModel?
    private var syntheticTimer: Timer?
    private var syntheticFrames: [PoseFrame] = []
    private var syntheticIndex = 0

    /// Plays a recorded landmark trace frame-by-frame into the engine (no camera) so the GUI
    /// can be exercised + screenshotted deterministically from synthetic data.
    func startSynthetic(viewModel: AppExerciseSessionViewModel, framesURL: URL) {
        self.viewModel = viewModel
        if viewModel.state.selectedExerciseID == nil, let first = viewModel.availablePresets.first {
            try? viewModel.selectPreset(id: first.id)
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
        errorText = nil
        running = true
        syntheticTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.syntheticIndex >= self.syntheticFrames.count {
                self.viewModel?.resetLiveSession()   // loop the trace for continuous animation
                self.syntheticIndex = 0
                return
            }
            self.viewModel?.ingestLiveFrame(self.syntheticFrames[self.syntheticIndex])
            self.syntheticIndex += 1
        }
    }

    func start(viewModel: AppExerciseSessionViewModel) {
        self.viewModel = viewModel
        if viewModel.state.selectedExerciseID == nil, let first = viewModel.availablePresets.first {
            try? viewModel.selectPreset(id: first.id)
        }
        viewModel.resetLiveSession()

        let paths = LiveWorkerPaths.resolve()
        let client = LivePoseWorkerClient(pythonURL: paths.python, scriptURL: paths.script, modelURL: paths.model)
        do {
            try client.start()
        } catch {
            errorText = "Pose worker failed to start: \(error.localizedDescription)"
            return
        }
        worker = client
        errorText = nil

        camera.onFrame = { [weak self] path, timestampMS, _ in
            guard let self, let worker = self.worker else { return }
            do {
                if let frame = try worker.predict(imagePath: path, frameID: Int(truncatingIfNeeded: timestampMS), timestampMS: timestampMS) {
                    DispatchQueue.main.async { self.viewModel?.ingestLiveFrame(frame) }
                }
            } catch {
                // transient per-frame error — drop this frame, keep going.
            }
        }
        camera.start()
        running = true
    }

    func stop() {
        syntheticTimer?.invalidate()
        syntheticTimer = nil
        camera.stop()
        camera.onFrame = nil
        worker?.stop()
        worker = nil
        running = false
    }
}

struct LiveCameraView: View {
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    @StateObject private var session = LiveSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CamiFit — Live").font(.headline)
                Spacer()
                Picker("Exercise", selection: exerciseBinding) {
                    ForEach(viewModel.availablePresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .frame(maxWidth: 220)
                .disabled(session.running)
                Button(session.running ? "Stop" : "Start") {
                    session.running ? session.stop() : session.start(viewModel: viewModel)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            ZStack {
                CameraPreview(session: session.camera.session)
                    .background(Color.black)
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
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 10)
                    }
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear { viewModel.loadAvailablePresets() }
        .onDisappear { session.stop() }
    }

    private var hud: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text((viewModel.state.selectedExerciseName ?? "Exercise").uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                if let cue = viewModel.state.cueText {
                    Text(cue).font(.headline).foregroundStyle(.white)
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 0) {
                Text(primaryMetricValue)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(primaryMetricLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .frame(maxWidth: 420)
    }

    private var isHoldExercise: Bool {
        viewModel.availablePresets.first { $0.id == viewModel.state.selectedExerciseID }?.kind == .hold
    }

    private var primaryMetricValue: String {
        isHoldExercise ? String(format: "%.0f", viewModel.state.holdSeconds) : "\(viewModel.state.repCount)"
    }

    private var primaryMetricLabel: String { isHoldExercise ? "SEC" : "REPS" }

    private var exerciseBinding: Binding<String?> {
        Binding {
            viewModel.state.selectedExerciseID
        } set: { selectedID in
            if let selectedID { try? viewModel.selectPreset(id: selectedID) }
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
                Text("CamiFit — Synthetic Demo").font(.headline)
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
