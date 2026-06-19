import AVFoundation
import AppKit
import SwiftUI

@main
struct MotionReferenceRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recorder = ReferenceRecorderViewModel()

    var body: some Scene {
        WindowGroup {
            ReferenceRecorderView()
                .environmentObject(recorder)
                .frame(minWidth: 820, minHeight: 620)
                .task {
                    await recorder.prepareCamera()
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ReferenceRecorderView: View {
    @EnvironmentObject private var recorder: ReferenceRecorderViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(session: recorder.session)
                    .background(Color.black)

                if let countdown = recorder.countdown {
                    CountdownOverlay(countdown: countdown)
                }

                VStack {
                    HStack {
                        CaptureBadge(text: recorder.exerciseLabel)
                        Spacer()
                        CaptureBadge(text: recorder.statusBadge)
                    }
                    Spacer()
                }
                .padding(18)
            }
            .frame(width: 820, height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 14) {
                Button(action: recorder.primaryButtonTapped) {
                    Label(recorder.primaryButtonTitle, systemImage: recorder.primaryButtonIcon)
                        .frame(minWidth: 172)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!recorder.canUsePrimaryButton)

                VStack(alignment: .leading, spacing: 4) {
                    Text(recorder.statusText)
                        .font(.headline)
                        .lineLimit(1)
                    Text(recorder.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(18)
            .background(.regularMaterial)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CountdownOverlay: View {
    let countdown: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
            Text("\(countdown)")
                .font(.system(size: 128, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 18)
        }
    }
}

struct CaptureBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.56), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.videoPreviewLayer.session = session
    }
}

final class PreviewContainerView: NSView {
    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("PreviewContainerView must be backed by AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
}

@MainActor
final class ReferenceRecorderViewModel: NSObject, ObservableObject {
    enum RecorderState {
        case waitingForCamera
        case ready
        case countingDown
        case recording
        case finished(URL)
        case failed(String)
    }

    nonisolated(unsafe) let session = AVCaptureSession()

    @Published private(set) var state: RecorderState = .waitingForCamera
    @Published private(set) var countdown: Int?
    @Published private(set) var lastOutputURL: URL?

    private let sessionQueue = DispatchQueue(label: "com.camifit.motion-reference-recorder.session")
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    private var captureTask: Task<Void, Never>?
    private var activeOutputURL: URL?
    private var isSessionConfigured = false

    private let countdownSeconds = 5
    private let exercise = CaptureExercise.current

    var exerciseLabel: String {
        exercise.label
    }

    var statusBadge: String {
        switch state {
        case .waitingForCamera:
            return "Camera"
        case .ready:
            return "Ready"
        case .countingDown:
            return "Countdown"
        case .recording:
            return "Recording"
        case .finished:
            return "Saved"
        case .failed:
            return "Needs attention"
        }
    }

    var statusText: String {
        switch state {
        case .waitingForCamera:
            return "Preparing camera"
        case .ready:
            return "Ready to capture"
        case .countingDown:
            return exercise.countdownTitle
        case .recording:
            return "Recording \(exercise.shortName) reference"
        case .finished:
            return "Capture saved"
        case .failed(let message):
            return message
        }
    }

    var detailText: String {
        switch state {
        case .waitingForCamera:
            return "Allow camera access if macOS asks."
        case .ready:
            return "Click Start. You will get a \(countdownSeconds) second countdown and an \(exercise.recordingSeconds) second recording."
        case .countingDown:
            return exercise.setupInstruction
        case .recording:
            return exercise.actionInstruction
        case .finished(let url):
            return url.path
        case .failed:
            return "Check camera permission in System Settings, then relaunch this recorder."
        }
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording:
            return "Stop Recording"
        case .countingDown:
            return "Cancel Countdown"
        default:
            return "Start Capture"
        }
    }

    var primaryButtonIcon: String {
        switch state {
        case .recording:
            return "stop.fill"
        case .countingDown:
            return "xmark"
        default:
            return "record.circle"
        }
    }

    var canUsePrimaryButton: Bool {
        switch state {
        case .waitingForCamera, .failed:
            return false
        default:
            return true
        }
    }

    func prepareCamera() async {
        guard !isSessionConfigured else { return }

        let isAuthorized = await requestCameraAccess()
        guard isAuthorized else {
            state = .failed("Camera access denied")
            return
        }

        configureSession()
    }

    func primaryButtonTapped() {
        switch state {
        case .countingDown:
            captureTask?.cancel()
            captureTask = nil
            countdown = nil
            state = .ready
        case .recording:
            stopRecording()
        default:
            startTimedCapture()
        }
    }

    private func startTimedCapture() {
        guard canUsePrimaryButton else { return }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            state = .countingDown

            for value in stride(from: countdownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdown = value
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled else { return }
            countdown = nil
            startRecording()

            try? await Task.sleep(for: .seconds(exercise.recordingSeconds))
            guard !Task.isCancelled else { return }
            stopRecording()
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSession() {
        isSessionConfigured = true
        state = .waitingForCamera

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            do {
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    throw RecorderError.cameraUnavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    throw RecorderError.cameraInputUnavailable
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.movieOutput) else {
                    throw RecorderError.movieOutputUnavailable
                }
                self.session.addOutput(self.movieOutput)

                if let connection = self.movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            } catch {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.state = .failed(error.localizedDescription)
                }
                return
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            Task { @MainActor in
                self.state = .ready
            }
        }
    }

    private func startRecording() {
        guard !movieOutput.isRecording else { return }

        let outputURL = makeCaptureURL()
        activeOutputURL = outputURL
        lastOutputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        state = .recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    private func stopRecording() {
        captureTask?.cancel()
        captureTask = nil
        countdown = nil

        if movieOutput.isRecording {
            movieOutput.stopRecording()
        } else if let outputURL = activeOutputURL {
            state = .finished(outputURL)
        } else {
            state = .ready
        }
    }

    private func makeCaptureURL() -> URL {
        let timestamp = Self.timestamp()
        let directory = Self.repoRoot()
            .appendingPathComponent("dist", isDirectory: true)
            .appendingPathComponent("motion-reference", isDirectory: true)
            .appendingPathComponent(exercise.id, isDirectory: true)
            .appendingPathComponent("user_capture_\(timestamp)", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(exercise.id)_reference.mov")
    }

    private func writeManifest(for outputURL: URL) {
        let manifestURL = outputURL.deletingLastPathComponent().appendingPathComponent("capture_manifest.json")
        let manifest = CaptureManifest(
            exerciseID: exercise.id,
            sourceKind: "first_party_webcam_reference_video",
            video: outputURL.lastPathComponent,
            countdownSeconds: countdownSeconds,
            recordingSeconds: exercise.recordingSeconds,
            captureNotes: exercise.captureNotes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private static func repoRoot() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["CAMIFIT_REPO_ROOT"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct CaptureExercise {
    let id: String
    let label: String
    let shortName: String
    let recordingSeconds: Int
    let countdownTitle: String
    let setupInstruction: String
    let actionInstruction: String
    let captureNotes: [String]

    static var current: CaptureExercise {
        let env = ProcessInfo.processInfo.environment
        let requestedID = env["CAMIFIT_CAPTURE_EXERCISE_ID"] ?? "bodyweight_pushup"
        return presets[requestedID] ?? presets["bodyweight_pushup"]!
    }

    private static let presets: [String: CaptureExercise] = [
        "bodyweight_pushup": CaptureExercise(
            id: "bodyweight_pushup",
            label: "Bodyweight Push-up Reference",
            shortName: "push-up",
            recordingSeconds: 8,
            countdownTitle: "Get into push-up position",
            setupInstruction: "Side view works best: hands, shoulders, hips, knees, ankles, and toes visible.",
            actionInstruction: "Do one clean controlled rep if possible, keeping hands and toes planted.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "Hands, toes, shoulders, hips, knees, and ankles should remain visible."
            ]
        ),
        "bodyweight_squat": CaptureExercise(
            id: "bodyweight_squat",
            label: "Bodyweight Squat Reference",
            shortName: "squat",
            recordingSeconds: 8,
            countdownTitle: "Stand side-on for squat capture",
            setupInstruction: "Side view works best: full body visible, feet planted, hips, knees, ankles, and shoulders in frame.",
            actionInstruction: "Do one or two slow controlled squats, finishing back at the top position.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "Full body should remain visible with both feet planted through each squat."
            ]
        ),
        "bodyweight_lunge": CaptureExercise(
            id: "bodyweight_lunge",
            label: "Bodyweight Lunge Reference",
            shortName: "lunge",
            recordingSeconds: 8,
            countdownTitle: "Set up a side-view split stance",
            setupInstruction: "Keep the full body visible; front foot and rear toe should stay planted.",
            actionInstruction: "Do one slow stationary lunge cycle without switching legs.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "Stationary split stance; front foot and rear toe should remain planted."
            ]
        ),
        "bodyweight_plank": CaptureExercise(
            id: "bodyweight_plank",
            label: "Bodyweight Plank Reference",
            shortName: "plank",
            recordingSeconds: 8,
            countdownTitle: "Set up a side-view plank",
            setupInstruction: "Side view works best: shoulders, hips, ankles, elbows or hands, and toes visible.",
            actionInstruction: "Hold a clean plank position until the recording finishes.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "Hold a stable body line with contact points visible."
            ]
        ),
        "bodyweight_jumping_jack": CaptureExercise(
            id: "bodyweight_jumping_jack",
            label: "Bodyweight Jumping Jack Reference",
            shortName: "jumping jack",
            recordingSeconds: 8,
            countdownTitle: "Stand front-facing for jumping jacks",
            setupInstruction: "Front view works best: full body visible, with wrists, shoulders, hips, knees, and ankles in frame.",
            actionInstruction: "Do one or two controlled jumping jacks, finishing with arms by your sides and feet together.",
            captureNotes: [
                "Front-view webcam capture for MediaPipe pose extraction.",
                "Wrists, shoulders, hips, knees, and ankles should remain visible through the full closed-open-closed cycle."
            ]
        ),
        "standing_miniband_hip_flexion": CaptureExercise(
            id: "standing_miniband_hip_flexion",
            label: "Standing Miniband Hip Flexion Reference",
            shortName: "hip flexion",
            recordingSeconds: 8,
            countdownTitle: "Stand side-on for hip flexion",
            setupInstruction: "Side view works best: shoulders, hips, knees, ankles, and the planted stance foot visible.",
            actionInstruction: "Do one or two controlled knee drives, returning to tall standing each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The stance foot should stay planted while the working knee drives forward and up; miniband tension is not pose-visible."
            ]
        ),
        "resistance_band_reverse_curl": CaptureExercise(
            id: "resistance_band_reverse_curl",
            label: "Resistance Band Reverse Curl Reference",
            shortName: "reverse curl",
            recordingSeconds: 8,
            countdownTitle: "Stand side-on for reverse curls",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, and the full curling arm visible.",
            actionInstruction: "Do one or two controlled reverse curls, returning to a straight arm each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The elbow flexion cycle and upper-arm stability are pose-visible; band tension and pronated grip are not."
            ]
        ),
        "bodyweight_pike": CaptureExercise(
            id: "bodyweight_pike",
            label: "Bodyweight Pike Reference",
            shortName: "pike",
            recordingSeconds: 8,
            countdownTitle: "Set up a side-view high plank",
            setupInstruction: "Side view works best: shoulders, elbows, wrists, hips, knees, ankles, hands, and toes visible.",
            actionInstruction: "Do one or two controlled high-plank to pike reps, returning to a long plank each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "Hands and toes should stay planted while hips lift into the pike; knees and elbows should remain long."
            ]
        ),
        "single_arm_dumbbell_preacher_curl": CaptureExercise(
            id: "single_arm_dumbbell_preacher_curl",
            label: "Single-Arm Dumbbell Preacher Curl Reference",
            shortName: "preacher curl",
            recordingSeconds: 8,
            countdownTitle: "Set up side-on for preacher curls",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, and the full working arm visible.",
            actionInstruction: "Do one or two controlled single-arm preacher curls, returning to a straight elbow each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The elbow flexion cycle and upper-arm stability are pose-visible; dumbbell load and bench support are setup/equipment requirements."
            ]
        ),
        "wide_grip_preacher_curl_with_ez_bar": CaptureExercise(
            id: "wide_grip_preacher_curl_with_ez_bar",
            label: "Wide-Grip Preacher Curl with EZ Bar Reference",
            shortName: "EZ-bar preacher curl",
            recordingSeconds: 8,
            countdownTitle: "Set up side-on for EZ-bar preacher curls",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, and the camera-side arm visible.",
            actionInstruction: "Do one or two controlled EZ-bar preacher curls, returning to straight elbows each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The camera-side elbow flexion cycle and upper-arm stability are pose-visible; EZ-bar presence, load, grip width, both-arm symmetry, and bench contact are setup/equipment requirements."
            ]
        ),
        "single_arm_chest_supported_incline_row": CaptureExercise(
            id: "single_arm_chest_supported_incline_row",
            label: "Single-Arm Chest-Supported Incline Row Reference",
            shortName: "incline row",
            recordingSeconds: 8,
            countdownTitle: "Set up side-on for the incline row",
            setupInstruction: "Side view works best: left shoulder, elbow, wrist, hip, and the full rowing arm visible.",
            actionInstruction: "Do one or two controlled left-arm rows, returning to a long arm each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The left elbow row cycle and shoulder path are pose-visible; dumbbell load, bench incline, chest contact, and grip path are setup/equipment requirements."
            ]
        ),
        "machine_chest_supported_row": CaptureExercise(
            id: "machine_chest_supported_row",
            label: "Machine - Chest-Supported Row Reference",
            shortName: "machine row",
            recordingSeconds: 8,
            countdownTitle: "Set up side-on for the machine row",
            setupInstruction: "Side view works best: visible shoulder, elbow, wrist, hip, and the full rowing arm visible.",
            actionInstruction: "Do one or two controlled chest-supported machine rows, returning to a long arm each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The visible elbow row cycle and shoulder path are pose-visible; machine load, handle style, chest-pad contact, and both-arm symmetry are setup/equipment requirements."
            ]
        ),
        "bench_lying_single_arm_dumbbell_tricep_extension": CaptureExercise(
            id: "bench_lying_single_arm_dumbbell_tricep_extension",
            label: "Bench-Lying Single-Arm Dumbbell Tricep Extension Reference",
            shortName: "lying tricep extension",
            recordingSeconds: 8,
            countdownTitle: "Lie side-on for tricep extensions",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, and the full working arm visible.",
            actionInstruction: "Do one or two controlled single-arm tricep extensions, returning to a straight elbow each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The elbow flexion-extension cycle and upper-arm stability are pose-visible; dumbbell load and flat-bench support are setup/equipment requirements."
            ]
        ),
        "single_arm_cable_tricep_extension": CaptureExercise(
            id: "single_arm_cable_tricep_extension",
            label: "Single-Arm Cable Tricep Extension Reference",
            shortName: "cable tricep extension",
            recordingSeconds: 8,
            countdownTitle: "Stand side-on for cable tricep extensions",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, and the full working arm visible.",
            actionInstruction: "Do one or two controlled cable tricep extensions, pressing down and returning to a bent elbow each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The elbow extension-return cycle and upper-arm stability are pose-visible; cable load and handle attachment are setup/equipment requirements."
            ]
        ),
        "suspension_tricep_press": CaptureExercise(
            id: "suspension_tricep_press",
            label: "Suspension Tricep Press Reference",
            shortName: "suspension tricep press",
            recordingSeconds: 8,
            countdownTitle: "Lean side-on into the suspension trainer",
            setupInstruction: "Side view works best: shoulder, elbow, wrist, hip, knee, ankle, and the full pressing arm visible.",
            actionInstruction: "Do one or two controlled suspension tricep presses, pressing out and returning to bent elbows each time.",
            captureNotes: [
                "Side-view webcam capture for MediaPipe pose extraction.",
                "The elbow press-out cycle and body-line posture are pose-visible; strap anchor, handle grip, and suspension load are setup/equipment requirements."
            ]
        )
    ]
}

private struct CaptureManifest: Encodable {
    let exerciseID: String
    let sourceKind: String
    let video: String
    let countdownSeconds: Int
    let recordingSeconds: Int
    let captureNotes: [String]

    private enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case sourceKind = "source_kind"
        case video
        case countdownSeconds = "countdown_seconds"
        case recordingSeconds = "recording_seconds"
        case captureNotes = "capture_notes"
    }
}

extension ReferenceRecorderViewModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.captureTask?.cancel()
            self.captureTask = nil
            self.countdown = nil

            if let error {
                self.state = .failed(error.localizedDescription)
                return
            }

            self.writeManifest(for: outputFileURL)
            self.lastOutputURL = outputFileURL
            self.activeOutputURL = nil
            self.state = .finished(outputFileURL)
            print("motion-reference capture_saved=\(outputFileURL.path)")
        }
    }
}

enum RecorderError: LocalizedError {
    case cameraUnavailable
    case cameraInputUnavailable
    case movieOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No camera was found"
        case .cameraInputUnavailable:
            return "Camera input could not be added"
        case .movieOutputUnavailable:
            return "Movie recording output could not be added"
        }
    }
}
