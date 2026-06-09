import CamiFitEngine
import Combine
import Foundation
import SwiftUI

private enum CamiFitLaunchEnvironment {
    static var guideExerciseID: String? {
        guard let id = ProcessInfo.processInfo.environment["CAMIFIT_GUIDE_EXERCISE"],
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return id
    }

    static var startsInGuideMode: Bool {
        guideExerciseID != nil
    }
}

final class SidebarSettingsPrompt: ObservableObject {
    @Published var generation = 0

    func showCameraSettings() {
        generation += 1
    }
}

struct ContentView: View {
    @EnvironmentObject private var onboarding: OnboardingCoordinator
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    @ObservedObject var codex: CodexAppServerClient
    @AppStorage("camifit.onboarding.completed") private var didCompleteOnboarding = false
    @StateObject private var routineRunner: RoutineRunner
    @StateObject private var liveSession = LiveSession()
    @StateObject private var chat = ChatViewModel()
    @StateObject private var exerciseMode = ExerciseModeController()
    @StateObject private var memoryStore = KGMemoryStore()
    @StateObject private var settingsPrompt = SidebarSettingsPrompt()
    @StateObject private var routineLibrary = RoutineLibraryStore()
    @State private var inspectorState = AppInspectorState()
    @State private var lastDebriefedReport: WorkoutCompletionReport?

    init(viewModel: AppExerciseSessionViewModel, codex: CodexAppServerClient) {
        self.viewModel = viewModel
        self.codex = codex
        _routineRunner = StateObject(wrappedValue: RoutineRunner(viewModel: viewModel))
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
        } detail: {
            DetailScene()
                .toolbar {
                    ToolbarSpacer(.flexible)

                    ToolbarItemGroup {
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            viewModel.resetLiveSession()
                            chat.resetSession()
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                        .help("Reset exercise and chat session")

                        Button {
                            onboarding.showTour()
                        } label: {
                            Label("Tour", systemImage: "questionmark.circle")
                        }
                        .help("Show the Future Coach feature tour")
                    }

                    ToolbarItem {
                        Button {
                            withAnimation(.smooth) { inspectorState.toggleCoach() }
                        } label: {
                            Label("Chat", systemImage: inspectorState.isActive(.coach) ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        }
                        .help("Toggle coach chat")
                    }

                    ToolbarItem {
                        Button {
                            withAnimation(.smooth) { inspectorState.showMemory() }
                        } label: {
                            Image(systemName: inspectorState.isActive(.memory) ? "brain.head.profile.fill" : "brain.head.profile")
                        }
                        .help("Memories")
                    }
                }
                .inspector(isPresented: $inspectorState.isPresented) {
                    Group {
                        switch inspectorState.mode {
                        case .coach:
                            ChatPanel()
                        case .memory:
                            KGMemoryPanel(store: memoryStore)
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 380)
                }
        }
        .navigationTitle("Momentum")
        .navigationSubtitle("A Future Coach")
        .sheet(isPresented: $onboarding.isPresented, onDismiss: completeOnboardingIfNeeded) {
            OnboardingFlowView(onFinish: {
                didCompleteOnboarding = true
                onboarding.dismiss()
            })
        }
        .environmentObject(viewModel)
        .environmentObject(liveSession)
        .environmentObject(chat)
        .environmentObject(codex)
        .environmentObject(routineLibrary)
        .environmentObject(routineRunner)
        .environmentObject(settingsPrompt)
        .environmentObject(exerciseMode)
        .onAppear {
            viewModel.loadAvailablePresets()
            if let guideExerciseID = CamiFitLaunchEnvironment.guideExerciseID {
                try? viewModel.selectPreset(id: guideExerciseID)
                try? routineRunner.startExercise(exerciseID: guideExerciseID, mode: .guide)
                didCompleteOnboarding = true
                onboarding.dismiss()
            }
            viewModel.loadRecordedRuns()
            routineLibrary.load()
            liveSession.refreshCameras()
            liveSession.requestCameraSettingsIfNoCameras()
            chat.codex = codex
            chat.memoryStore = memoryStore
            chat.coachActionDispatcher = CoachActionDispatcher(
                viewModel: viewModel,
                routineRunner: routineRunner,
                modeController: exerciseMode
            )
            codex.start()
            memoryStore.load()
            routineRunner.updateCameraReadiness(liveSession.camera.readiness)
            routineRunner.updatePoseReadiness(liveSession.poseReadiness)
            if !didCompleteOnboarding {
                DispatchQueue.main.async {
                    onboarding.showTour()
                }
            }
        }
        .onDisappear {
            routineRunner.cancel()
            liveSession.stop()
            codex.stop()
        }
        .onReceive(routineRunner.$lastCompletionReport) { report in
            guard let report, report != lastDebriefedReport else { return }
            lastDebriefedReport = report
            chat.requestWorkoutDebrief(for: report)
        }
        .onReceive(liveSession.$cameraSettingsPromptID.compactMap { $0 }) { _ in
            settingsPrompt.showCameraSettings()
        }
    }

    private func completeOnboardingIfNeeded() {
        if !didCompleteOnboarding {
            didCompleteOnboarding = true
        }
    }
}

enum AppInspectorMode: Equatable {
    case coach
    case memory
}

struct AppInspectorState: Equatable {
    var isPresented = true
    var mode: AppInspectorMode = .coach

    mutating func toggleCoach() {
        if isPresented && mode == .coach {
            isPresented = false
        } else {
            showCoach()
        }
    }

    mutating func showCoach() {
        mode = .coach
        isPresented = true
    }

    mutating func showMemory() {
        mode = .memory
        isPresented = true
    }

    func isActive(_ candidate: AppInspectorMode) -> Bool {
        isPresented && mode == candidate
    }
}

// MARK: - Detail

private struct DetailScene: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @EnvironmentObject private var liveSession: LiveSession
    @StateObject private var formCheck = FormCheckController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeroPreviewCard(liveSession: liveSession, formCheck: formCheck)

                ZStack(alignment: .topLeading) {
                    TrainingContextPanel(formCheck: formCheck)
                        .id(trainingContextIdentity)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.smooth(duration: 0.30), value: trainingContextIdentity)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .background {
            DetailBackdrop()
        }
    }

    private var trainingContextIdentity: String {
        if let routine = routineRunner.currentRoutine,
           let block = routineRunner.currentBlock {
            return "routine:\(routine.id):\(routineRunner.activeBlockIndex):\(block.program.id)"
        }
        return "exercise:\(model.state.selectedExerciseID ?? "none")"
    }
}

private struct DetailBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Hero preview

private struct HeroPreviewCard: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @EnvironmentObject private var exerciseMode: ExerciseModeController
    @ObservedObject var liveSession: LiveSession
    @ObservedObject var formCheck: FormCheckController
    @State private var feedMode: HeroFeedMode = CamiFitLaunchEnvironment.startsInGuideMode ? .avatarGuide : .tracking
    @State private var showsSkeletonOverlay = true
    @State private var repPulseStrength: CGFloat = 0
    @State private var repPulseGeneration = 0

    private var displayedFeedMode: HeroFeedMode {
        routineRunner.phase.usesGuide ? .avatarGuide : feedMode
    }

    private var guideToggleTitle: String {
        displayedFeedMode == .avatarGuide ? "Camera" : "Guide"
    }

    private var guideToggleSystemImage: String {
        displayedFeedMode == .avatarGuide ? "video.fill" : "figure.strengthtraining.functional"
    }

    private var guideToggleTint: Color {
        displayedFeedMode == .avatarGuide ? .cyan : .secondary
    }

    private var guideToggleHelp: String {
        displayedFeedMode == .avatarGuide
            ? "Return to camera tracking"
            : "Show the avatar guide for the selected exercise"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PoseStage(
                liveSession: liveSession,
                feedMode: displayedFeedMode,
                showsSkeletonOverlay: showsSkeletonOverlay,
                showsFormTarget: formCheck.isActive,
                formMatchProgress: formCheck.progress(for: model.state, target: currentFormTarget)
            )

            if displayedFeedMode != .avatarGuide {
                VStack(alignment: .leading) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(heroStats) { stat in
                            StatTile(stat: stat)
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer()
                }
                .padding(14)
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    if !routineRunner.phase.usesGuide {
                        Button {
                            withAnimation(.smooth) {
                                if displayedFeedMode == .avatarGuide {
                                    feedMode = .tracking
                                } else {
                                    liveSession.stop()
                                    model.resetLiveSession()
                                    feedMode = .avatarGuide
                                }
                            }
                        } label: {
                            Label(guideToggleTitle, systemImage: guideToggleSystemImage)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(guideToggleTint)
                        .help(guideToggleHelp)
                    }
                }
                Spacer()
            }
            .padding(14)

            RoutinePhaseOverlay(
                phase: routineRunner.phase,
                pipelineStatus: liveSession.poseReadiness.displayText,
                progressText: routineRunner.progressText,
                onResume: { routineRunner.resume() },
                onEnd: {
                    routineRunner.cancel()
                    liveSession.stop()
                },
                onRestart: { routineRunner.restartCurrentSet() }
            )

            if let cueText = model.state.cueText {
                VStack {
                    Spacer()
                    HStack {
                        CueBanner(text: cueText)
                        Spacer(minLength: 0)
                    }
                    Spacer().frame(height: 56)
                }
                .padding(14)
            }

            VStack {
                Spacer()
                ActionControlBar(
                    liveSession: liveSession,
                    feedMode: $feedMode,
                    showsSkeletonOverlay: $showsSkeletonOverlay
                )
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .backgroundExtensionEffect()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .overlay(
            HeroRepPulseOverlay(strength: repPulseStrength)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .onChange(of: routineRunner.phase) { _, phase in
            syncLivePipeline(for: phase)
        }
        .onChange(of: model.state.repCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            triggerRepPulse()
        }
        .onReceive(liveSession.camera.$readiness) { readiness in
            routineRunner.updateCameraReadiness(readiness)
        }
        .onReceive(liveSession.$poseReadiness) { readiness in
            routineRunner.updatePoseReadiness(readiness)
        }
        .onAppear {
            syncLivePipeline(for: routineRunner.phase)
        }
        .onChange(of: model.state.selectedExerciseID) { _, _ in
            formCheck.cancel()
        }
        .onChange(of: routineRunner.phase) { _, phase in
            if case .idle = phase {
                formCheck.cancel()
            }
        }
        .onChange(of: exerciseMode.current) { _, request in
            guard let request else { return }
            applyExerciseModeRequest(request)
        }
    }

    private var heroStats: [HeroStat] {
        var stats: [HeroStat] = []

        if let exerciseName = currentExerciseName {
            stats.append(
                HeroStat(
                    label: "Exercise",
                    value: exerciseName,
                    detail: routineRunner.isRoutineBackedRun ? routineRunner.currentRoutine?.name : nil,
                    systemImage: "figure.strengthtraining.functional",
                    minWidth: 132
                )
            )
        }

        if let setStat {
            stats.append(setStat)
        }

        if let targetStat {
            stats.append(targetStat)
        } else {
            stats.append(HeroStat(label: "Reps", value: "\(model.state.repCount)", systemImage: "repeat"))
        }

        if let scoreText = model.state.scoreText, !scoreText.isEmpty {
            stats.append(HeroStat(label: "Score", value: scoreText, systemImage: "rosette"))
        }

        return stats
    }

    private var currentExerciseName: String? {
        if case .rest = routineRunner.phase {
            return routineRunner.nextBlockTitle ?? routineRunner.currentBlock?.title
        }
        return routineRunner.currentBlock?.title ?? model.state.selectedExerciseName
    }

    private var setStat: HeroStat? {
        guard let block = routineRunner.currentBlock else { return nil }
        let currentSet = min(routineRunner.cursor.setIndex + 1, block.sets.count)
        return HeroStat(
            label: "Set",
            value: "\(currentSet)/\(block.sets.count)",
            detail: routineRunner.routineStepText,
            systemImage: "list.number",
            minWidth: 82
        )
    }

    private var targetStat: HeroStat? {
        guard let target = currentFormTarget else { return nil }
        switch target {
        case let .reps(reps):
            return HeroStat(
                label: "Reps",
                value: "\(min(model.state.repCount, reps))/\(reps)",
                systemImage: "repeat",
                minWidth: 88
            )
        case let .holdSeconds(seconds):
            let elapsed = SetTarget.formatSeconds(min(model.state.holdSeconds, seconds))
            let target = SetTarget.formatSeconds(seconds)
            return HeroStat(
                label: "Hold",
                value: "\(elapsed)/\(target)s",
                systemImage: "timer",
                minWidth: 88
            )
        }
    }

    private var currentFormTarget: SetTarget? {
        if let target = routineRunner.currentSet?.target {
            return target
        }
        guard let program = model.activeExerciseProgram else { return nil }
        return SetTarget.defaultTarget(for: program)
    }

    private func syncLivePipeline(for phase: RoutineRunPhase) {
        if phase.usesGuide {
            liveSession.stop()
            feedMode = .avatarGuide
            return
        }

        if phase.needsCamera {
            feedMode = .tracking
            ensureRoutineLiveCamera()
        } else if case .complete = phase {
            liveSession.stop()
        } else if case .failed = phase {
            liveSession.stop()
        }
    }

    private func ensureRoutineLiveCamera() {
        if liveSession.running, liveSession.isLiveCamera, liveSession.routesPoseFramesExternally {
            return
        }
        liveSession.stop()
        liveSession.start(viewModel: model) { frame in
            routineRunner.ingest(frame)
        }
    }

    private func triggerRepPulse() {
        repPulseGeneration += 1
        let generation = repPulseGeneration

        withAnimation(.easeOut(duration: 0.16)) {
            repPulseStrength = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard generation == repPulseGeneration else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                repPulseStrength = 0
            }
        }
    }

    private func applyExerciseModeRequest(_ request: ExerciseModeRequest) {
        guard model.state.selectedExerciseID == request.exerciseID else { return }

        switch request.mode {
        case .guide:
            liveSession.stop()
            formCheck.cancel()
            feedMode = .avatarGuide
        case .camera:
            formCheck.cancel()
            if routineRunner.phase.needsCamera {
                feedMode = .tracking
                ensureRoutineLiveCamera()
            } else {
                liveSession.stop()
                feedMode = .avatarGuide
            }
        case .matchForm:
            formCheck.begin(current: model.state)
            if routineRunner.phase.needsCamera {
                feedMode = .tracking
                ensureRoutineLiveCamera()
            } else {
                liveSession.stop()
                feedMode = .avatarGuide
            }
        }
    }
}

enum HeroFeedMode: Equatable {
    case tracking
    case avatarGuide
}

struct PoseStageDisplayState: Equatable {
    let feedMode: HeroFeedMode
    let isRunning: Bool
    let isLiveCamera: Bool

    var showsStoredPoseOverlay: Bool {
        feedMode == .tracking && isRunning && !isLiveCamera
    }

    var showsStoppedPlaceholder: Bool {
        feedMode == .tracking && !isRunning
    }
}

private struct PoseStage: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @ObservedObject var liveSession: LiveSession
    let feedMode: HeroFeedMode
    let showsSkeletonOverlay: Bool
    let showsFormTarget: Bool
    let formMatchProgress: Double

    private var displayState: PoseStageDisplayState {
        PoseStageDisplayState(
            feedMode: feedMode,
            isRunning: liveSession.running,
            isLiveCamera: liveSession.isLiveCamera
        )
    }

    var body: some View {
        ZStack {
            if feedMode == .avatarGuide {
                AvatarDemoStage()
            } else if liveSession.running && liveSession.isLiveCamera {
                CameraPreview(session: liveSession.camera.session)
                    .background(Color.black)
                if showsSkeletonOverlay {
                    LivePoseOverlay(state: model.latestPoseOverlayState, sourceSize: liveSession.sourceSize)
                        .allowsHitTesting(false)
                }
            } else {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.02, green: 0.03, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if displayState.showsStoredPoseOverlay {
                    PoseOverlayView(state: model.latestPoseOverlayState)
                        .padding(18)
                }

                if displayState.showsStoppedPlaceholder {
                    placeholderOverlay
                }
            }

            if showsFormTarget, feedMode == .tracking, let program = model.activeExerciseProgram {
                FormTargetOverlay(
                    program: program,
                    progress: formMatchProgress,
                    sourceSize: liveSession.sourceSize
                )
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let errorText = liveSession.errorText {
                VStack {
                    Spacer()
                    Text(errorText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .glassEffect(.regular.tint(.red.opacity(0.32)), in: .rect(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 72)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var placeholderOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 36, weight: .regular))
            Text("No pose data yet")
                .font(.title3.weight(.semibold))
            Text("Press Live Camera for webcam tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }
}

private struct CueBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.black.opacity(0.22)), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct HeroRepPulseOverlay: View {
    let strength: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.54 * Double(strength)), lineWidth: 2.5)
                .shadow(color: .green.opacity(0.26 * Double(strength)), radius: 18 * strength)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.22 * Double(strength)), lineWidth: 9)
                .blur(radius: 4)
                .padding(1)
        }
        .opacity(Double(strength))
        .allowsHitTesting(false)
    }
}

private struct RoutinePhaseOverlay: View {
    let phase: RoutineRunPhase
    let pipelineStatus: String
    let progressText: String?
    let onResume: () -> Void
    let onEnd: () -> Void
    let onRestart: () -> Void

    var body: some View {
        switch phase {
        case .idle, .working:
            EmptyView()
        case .preparing:
            overlay(title: "Routine starting", detail: nil, symbol: "play.circle.fill")
        case .guide:
            EmptyView()
        case let .awaitingCamera(readiness):
            overlay(title: "Waiting for camera", detail: readiness.displayText, symbol: "video.fill")
        case let .awaitingPose(message):
            overlay(title: message ?? "Step into frame", detail: pipelineStatus, symbol: "figure.walk.motion")
        case let .countdown(secondsRemaining):
            overlay(title: "\(secondsRemaining)", detail: "Get ready", symbol: "timer")
        case .rest:
            EmptyView()
        case .paused:
            overlay(
                title: "Paused",
                detail: progressText ?? "Resume when ready",
                symbol: "pause.circle.fill",
                actions: {
                    Button("Resume", action: onResume)
                    Button("Restart Exercise", action: onRestart)
                    Button("End Routine", role: .destructive, action: onEnd)
                }
            )
        case let .complete(summary):
            overlay(
                title: summary.scope == .exercise ? "Exercise complete" : "Routine complete",
                detail: summary.displayText,
                symbol: "checkmark.circle.fill",
                actions: {
                    Button("Done", action: onEnd)
                }
            )
        case let .failed(message):
            overlay(
                title: "Routine unavailable",
                detail: message,
                symbol: "exclamationmark.triangle.fill",
                actions: {
                    Button("Done", action: onEnd)
                }
            )
        }
    }

    private func overlay<Actions: View>(
        title: String,
        detail: String?,
        symbol: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                actions()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(minWidth: 180)
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func overlay(title: String, detail: String?, symbol: String) -> some View {
        overlay(title: title, detail: detail, symbol: symbol) {
            EmptyView()
        }
    }
}

private struct ActionControlBar: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @ObservedObject var liveSession: LiveSession
    @Binding var feedMode: HeroFeedMode
    @Binding var showsSkeletonOverlay: Bool

    private var liveActive: Bool { liveSession.running && liveSession.isLiveCamera }
    private var guideActive: Bool { routineRunner.phase.usesGuide }
    private var routineOwnsCamera: Bool { routineRunner.phase.needsCamera }
    private var guideSecondsRemaining: Int? {
        if case let .guide(secondsRemaining) = routineRunner.phase {
            return secondsRemaining
        }
        return nil
    }
    private var restSecondsRemaining: Int? {
        if case let .rest(secondsRemaining) = routineRunner.phase {
            return secondsRemaining
        }
        return nil
    }

    private var guideStatusText: String {
        guard let guideSecondsRemaining else {
            return "Guide"
        }
        return "\(guideSecondsRemaining)s Demo"
    }

    private var guidePrimaryTitle: String {
        routineRunner.isGuideOnlyExerciseRun ? "Start Practice" : "Start Set"
    }

    private var guidePrimarySymbol: String {
        routineRunner.isGuideOnlyExerciseRun ? "video.fill" : "forward.fill"
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if guideActive {
                    Label(guideStatusText, systemImage: "figure.strengthtraining.functional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .help("Guide demo")

                    if guideSecondsRemaining != nil {
                        Button {
                            routineRunner.replayGuide()
                        } label: {
                            Label("Replay", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .help("Replay guide")

                        Button {
                            startGuideAction()
                        } label: {
                            Label(guidePrimaryTitle, systemImage: guidePrimarySymbol)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.cyan)
                        .help(guidePrimaryTitle)
                    }
                } else {
                    Button {
                        if liveActive {
                            liveSession.stop()
                        } else if routineRunner.isGuideOnlyExerciseRun {
                            liveSession.stop()
                            feedMode = .tracking
                            routineRunner.startCurrentExercisePractice()
                            liveSession.start(viewModel: model) { frame in
                                routineRunner.ingest(frame)
                            }
                        } else {
                            liveSession.stop()
                            feedMode = .tracking
                            liveSession.start(viewModel: model)
                        }
                    } label: {
                        Label(liveActive ? "Stop" : (routineRunner.isGuideOnlyExerciseRun ? "Start Practice" : "Live Camera"),
                              systemImage: liveActive ? "stop.fill" : "video.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(liveActive ? .red : .accentColor)
                    .disabled(routineOwnsCamera)
                    .help(liveActive ? "Stop the live camera" : "Track reps from your webcam, in this window")

                    Toggle(isOn: $showsSkeletonOverlay) {
                        Label("Skeleton", systemImage: showsSkeletonOverlay ? "figure.walk.motion" : "figure.stand")
                    }
                    .toggleStyle(.checkbox)
                    .disabled(feedMode == .avatarGuide)
                    .help(feedMode == .avatarGuide
                          ? "The skeleton overlay is only available during live camera tracking"
                          : "Show or hide the skeleton overlay while using the live camera")

                    if liveActive {
                        Button {
                            liveSession.toggleRecording()
                        } label: {
                            Label(liveSession.recording ? "Stop Rec" : "Record",
                                  systemImage: liveSession.recording ? "stop.circle.fill" : "record.circle")
                        }
                        .buttonStyle(.glass)
                        .tint(liveSession.recording ? .red : .secondary)
                        .help("Record live camera frames to disk")
                    }
                }

                Spacer(minLength: 12)

                if let restSecondsRemaining {
                    Label("\(restSecondsRemaining)s Rest", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .help(restHelpText)

                    Button {
                        routineRunner.skipRest()
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                    }
                    .buttonStyle(.glass)
                    .help("Skip rest")

                    Button {
                        routineRunner.addRest(seconds: 15)
                    } label: {
                        Label("+15s", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                    .help("Add 15 seconds")
                }

                if !guideActive && (routineRunner.phase.isActive || routineRunner.isPaused) {
                    Button {
                        routineRunner.togglePause()
                    } label: {
                        Label(pauseTitle, systemImage: pauseIcon)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canTogglePause)
                    .help(pauseTitle)
                }

                Button {
                    if routineRunner.phase.isActive || routineRunner.isPaused {
                        routineRunner.restartCurrentSet()
                    } else {
                        model.resetLiveSession()
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .help("Reset reps, hold, and overlay")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var canTogglePause: Bool {
        routineRunner.canTogglePause
    }

    private var restHelpText: String {
        guard let nextBlockTitle = routineRunner.nextBlockTitle else {
            return "Rest timer"
        }
        return "Next: \(nextBlockTitle)"
    }

    private var pauseTitle: String {
        routineRunner.isPaused ? "Resume" : "Pause"
    }

    private var pauseIcon: String {
        routineRunner.isPaused ? "play.fill" : "pause.fill"
    }

    private func startGuideAction() {
        if routineRunner.isGuideOnlyExerciseRun {
            liveSession.stop()
            feedMode = .tracking
            routineRunner.startCurrentExercisePractice()
            liveSession.start(viewModel: model) { frame in
                routineRunner.ingest(frame)
            }
        } else {
            routineRunner.skipGuide()
        }
    }
}

// MARK: - Sidebar (session inputs)

private enum SidebarTab: String, CaseIterable {
    case settings
    case exercises
    case routines

    var title: String {
        switch self {
        case .settings: "Settings"
        case .exercises: "Exercises"
        case .routines: "Routines"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .exercises: "figure.strengthtraining.functional"
        case .routines: "list.bullet.rectangle"
        }
    }
}

private struct SessionSidebar: View {
    @EnvironmentObject private var settingsPrompt: SidebarSettingsPrompt
    @SceneStorage("camifit.sidebar.tab") private var selectedTabRaw = SidebarTab.settings.rawValue

    private var selectedTab: SidebarTab {
        SidebarTab(rawValue: selectedTabRaw) ?? .settings
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: selectedTabBinding) {
                ForEach(SidebarTab.allCases, id: \.rawValue) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.45)

            Group {
                switch selectedTab {
                case .settings:
                    SessionSettingsSidebar()
                case .exercises:
                    ExerciseLibrarySidebar()
                case .routines:
                    RoutineLibrarySidebar()
                }
            }
        }
        .navigationTitle(selectedTab.title)
        .onReceive(settingsPrompt.$generation.dropFirst()) { _ in
            selectedTabRaw = SidebarTab.settings.rawValue
        }
    }

    private var selectedTabBinding: Binding<SidebarTab> {
        Binding {
            selectedTab
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }
}

private struct SessionSettingsSidebar: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CameraSection()
                #if DEBUG
                DeveloperSection()
                #endif
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarDrillInPane<ListContent: View, DetailContent: View>: View {
    let isShowingDetail: Bool
    let backTitle: String
    let onBack: () -> Void
    private let list: () -> ListContent
    private let detail: () -> DetailContent

    init(
        isShowingDetail: Bool,
        backTitle: String,
        onBack: @escaping () -> Void,
        @ViewBuilder list: @escaping () -> ListContent,
        @ViewBuilder detail: @escaping () -> DetailContent
    ) {
        self.isShowingDetail = isShowingDetail
        self.backTitle = backTitle
        self.onBack = onBack
        self.list = list
        self.detail = detail
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isShowingDetail {
                detailPane
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .zIndex(1)
            } else {
                list()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.smooth(duration: 0.26), value: isShowingDetail)
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label(backTitle, systemImage: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.45)

            ScrollView {
                detail()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 14)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ExerciseLibrarySidebar: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @State private var focusedPresetID: String?

    var body: some View {
        SidebarDrillInPane(
            isShowingDetail: focusedPreset != nil,
            backTitle: "Exercises",
            onBack: { focusedPresetID = nil }
        ) {
            exerciseList
        } detail: {
            if let focusedPreset {
                ExerciseDetailPanel(preset: focusedPreset)
            } else {
                Text("Exercise unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { model.loadAvailablePresets() }
    }

    private var focusedPreset: AppPresetSummary? {
        guard let focusedPresetID else { return nil }
        return model.availablePresets.first { $0.id == focusedPresetID }
    }

    private var exerciseList: some View {
        List {
            if model.availablePresets.isEmpty {
                Text("No exercises available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.availablePresets) { preset in
                    Button {
                        open(preset)
                    } label: {
                        ExerciseSidebarRow(preset: preset, isSelected: preset.id == model.state.selectedExerciseID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func open(_ preset: AppPresetSummary) {
        select(preset)
        focusedPresetID = preset.id
    }

    private func select(_ preset: AppPresetSummary) {
        withAnimation(.smooth(duration: 0.30)) {
            routineRunner.cancel()
            try? model.selectPreset(id: preset.id)
        }
    }
}

private struct ExerciseSidebarRow: View {
    let preset: AppPresetSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: preset.kind == .reps ? "repeat" : "timer")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(preset.kind == .reps ? "Counts reps" : "Timed hold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct ExerciseDetailPanel: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    let preset: AppPresetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let program {
                let summary = RoutinePresentation.summary(for: program)
                SidebarMetricGrid(metrics: [
                    SidebarMetric(label: "Target", value: summary.targetText, systemImage: targetIcon(for: program)),
                    SidebarMetric(label: "Time", value: summary.estimatedSetText, systemImage: "clock"),
                    SidebarMetric(label: "View", value: summary.setupText, systemImage: "camera.viewfinder"),
                    SidebarMetric(label: "Tracking", value: summary.trackingText, systemImage: "point.3.connected.trianglepath.dotted")
                ])

                if !summary.cueTexts.isEmpty {
                    SidebarDetailSection(title: "Cues") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(summary.cueTexts, id: \.self) { cue in
                                Label(cue, systemImage: "waveform.path.ecg")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                Text("Exercise unavailable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
    }

    private var program: ExerciseProgram? {
        try? model.programForPreset(id: preset.id)
    }

    private var isActive: Bool {
        model.state.selectedExerciseID == preset.id
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: preset.kind == .reps ? "repeat" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(preset.kind == .reps ? .cyan : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(preset.kind == .reps ? "Counts reps" : "Timed hold")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
        }
    }

    private func targetIcon(for program: ExerciseProgram) -> String {
        program.hold == nil ? "target" : "timer"
    }
}

private struct SidebarMetric: Identifiable, Equatable {
    let label: String
    let value: String
    let systemImage: String

    var id: String { label }
}

private struct SidebarMetricGrid: View {
    let metrics: [SidebarMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(metrics) { metric in
                SidebarMetricCell(metric: metric)
            }
        }
    }
}

private struct SidebarMetricCell: View {
    let metric: SidebarMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.label, systemImage: metric.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(metric.value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }
}

private struct SidebarDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct RoutineLibrarySidebar: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineLibrary: RoutineLibraryStore
    @State private var focusedRoutineID: String?

    var body: some View {
        SidebarDrillInPane(
            isShowingDetail: focusedRoutine != nil,
            backTitle: "Routines",
            onBack: { focusedRoutineID = nil }
        ) {
            routineList
        } detail: {
            if let focusedRoutine {
                RoutineDetailPanel(routine: focusedRoutine)
            } else {
                Text("Routine unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            model.loadAvailablePresets()
            routineLibrary.load()
        }
    }

    private var focusedRoutine: WorkoutRoutine? {
        guard let focusedRoutineID else { return nil }
        return routineLibrary.routines.first { $0.id == focusedRoutineID }
    }

    private var routineList: some View {
        List {
            if routineLibrary.routines.isEmpty {
                Text("No saved routines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(routineLibrary.routines) { routine in
                    Button {
                        open(routine)
                    } label: {
                        RoutineSidebarRow(routine: routine, summary: summary(for: routine))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func open(_ routine: WorkoutRoutine) {
        routineLibrary.select(routine)
        focusedRoutineID = routine.id
    }

    private func summary(for routine: WorkoutRoutine) -> RoutinePresentationSummary {
        RoutinePresentation.summary(for: routine, compiler: compiler())
    }

    private func compiler() -> RoutineCompiler {
        RoutineCompiler { presetID in
            try model.programForPreset(id: presetID)
        }
    }
}

private struct RoutineSidebarRow: View {
    let routine: WorkoutRoutine
    let summary: RoutinePresentationSummary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(summary.isRunnable ? Color.accentColor : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(summary.compactDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private enum RoutineBlockRunStatus: Equatable {
    case ready(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .unavailable:
            return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case let .ready(target):
            return target
        case let .unavailable(message):
            return message
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unavailable:
            return .orange
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

private struct RoutineExerciseDisplay: Equatable {
    let targetText: String
    let estimateText: String
    let restText: String
    let kindText: String
    let status: RoutineBlockRunStatus
}

private struct RoutineDetailPanel: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    let routine: WorkoutRoutine
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let actionError {
                Text(actionError)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }

            SidebarDetailSection(title: "Exercises") {
                VStack(spacing: 8) {
                    ForEach(Array(routine.blocks.enumerated()), id: \.offset) { index, block in
                        RoutineDetailBlockRow(
                            index: index,
                            exerciseName: exerciseName(for: block.exerciseRef),
                            display: display(for: block),
                            onPractice: { practice(index) },
                            onStartFromHere: { startFrom(index) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            let summary = RoutinePresentation.summary(for: routine, compiler: compiler())

            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let description = routine.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SidebarMetricGrid(metrics: [
                SidebarMetric(label: "Exercises", value: "\(summary.exerciseCount)", systemImage: "figure.strengthtraining.functional"),
                SidebarMetric(label: "Sets", value: "\(summary.setCount)", systemImage: "repeat"),
                SidebarMetric(label: "Time", value: summary.durationText, systemImage: "clock"),
                SidebarMetric(label: "Status", value: summary.isRunnable ? "Ready" : "Unavailable", systemImage: summary.isRunnable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            ])

            Button {
                startFrom(0)
            } label: {
                Label("Start Routine", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!isRunnable)

            if !summary.isRunnable, let availabilityText = summary.availabilityText {
                Text(availabilityText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private var isRunnable: Bool {
        (try? compiler().compile(routine)) != nil
    }

    private func display(for block: RoutineBlock) -> RoutineExerciseDisplay {
        let single = WorkoutRoutine(
            id: "\(routine.id)-block",
            name: routine.name,
            blocks: [block]
        )
        do {
            let compiled = try compiler().compile(single)
            guard let executableBlock = compiled.blocks.first else {
                return unavailableDisplay(for: block, message: "Exercise unavailable")
            }
            return RoutineExerciseDisplay(
                targetText: RoutinePresentation.targetText(sets: executableBlock.source.sets, target: executableBlock.target),
                estimateText: RoutinePresentation.durationText(seconds: RoutinePresentation.estimatedSeconds(for: executableBlock)),
                restText: RoutinePresentation.restText(seconds: executableBlock.restSeconds),
                kindText: executableBlock.program.hold == nil ? "Rep exercise" : "Hold exercise",
                status: .ready("Ready")
            )
        } catch {
            return unavailableDisplay(for: block, message: RoutinePresentation.userFacingErrorText(String(describing: error)))
        }
    }

    private func unavailableDisplay(for block: RoutineBlock, message: String) -> RoutineExerciseDisplay {
        RoutineExerciseDisplay(
            targetText: fallbackTargetText(for: block),
            estimateText: "Estimate unavailable",
            restText: RoutinePresentation.restText(seconds: max(0, block.restSeconds ?? 0)),
            kindText: "Exercise",
            status: .unavailable(message)
        )
    }

    private func fallbackTargetText(for block: RoutineBlock) -> String {
        if let reps = block.reps {
            return RoutinePresentation.targetText(sets: block.sets, target: .reps(reps))
        }
        if let holdSeconds = block.holdSeconds {
            return RoutinePresentation.targetText(sets: block.sets, target: .holdSeconds(holdSeconds))
        }
        return "\(block.sets) \(block.sets == 1 ? "set" : "sets")"
    }

    private func startFrom(_ index: Int) {
        do {
            try routineRunner.start(routine, atBlock: index)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func practice(_ index: Int) {
        do {
            try routineRunner.practice(routine, blockIndex: index)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func compiler() -> RoutineCompiler {
        RoutineCompiler { presetID in
            try model.programForPreset(id: presetID)
        }
    }

    private func exerciseName(for ref: ExerciseRef) -> String {
        switch ref {
        case let .preset(id):
            return model.availablePresets.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "_", with: " ")
        case let .inline(program):
            return program.name
        }
    }
}

private struct RoutineDetailBlockRow: View {
    let index: Int
    let exerciseName: String
    let display: RoutineExerciseDisplay
    let onPractice: () -> Void
    let onStartFromHere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(exerciseName)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text(display.kindText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Label(display.status.label, systemImage: display.status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(display.status.tint)
                    .labelStyle(.iconOnly)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(display.targetText, systemImage: "target")
                Label(display.estimateText, systemImage: "clock")
                Label(display.restText, systemImage: "timer")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if !display.status.isReady {
                Text(display.status.detail)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button {
                    onPractice()
                } label: {
                    Label("Practice", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!display.status.isReady)

                Button {
                    onStartFromHere()
                } label: {
                    Label("Start Here", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!display.status.isReady)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
}

private struct CameraSection: View {
    @EnvironmentObject private var liveSession: LiveSession

    var body: some View {
        SidebarSettingsSection(title: "Camera") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Input")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Input", selection: $liveSession.selectedCameraID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(liveSession.availableCameras) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: liveSession.selectedCameraID) { _, newID in
                    liveSession.camera.setDevice(newID)
                }

                Text(cameraPromptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if liveSession.availableCameras.isEmpty {
                    Text("Connect a camera, then refresh this list.")
                        .font(.caption.weight(.semibold))
                } else {
                    Text("Select the connected camera you want CamiFit to use.")
                        .font(.caption.weight(.semibold))
                }

                Button {
                    liveSession.refreshCameras()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var cameraPromptText: String {
        if liveSession.availableCameras.isEmpty {
            return "No cameras detected."
        }

        return "Choose the webcam used by Live Camera."
    }
}

private struct SidebarSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }
}

// MARK: - Settings (Cmd+,)

struct CamiFitSettingsView: View {
    @EnvironmentObject private var codex: CodexAppServerClient

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                        Text(codex.accountDetail)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                accountActions
            } header: {
                Text("OpenAI Account")
            } footer: {
                Text("Future Coach signs in with your ChatGPT account through Codex. The coach uses this account for every reply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
        .onAppear { codex.refreshAccount() }
    }

    @ViewBuilder
    private var accountActions: some View {
        switch codex.account {
        case .signedIn:
            Button("Disconnect OpenAI Account", role: .destructive) {
                codex.logout()
            }
        case .pending:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser sign-in…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { codex.cancelLogin() }
            }
        case .signedOut, .unknown:
            HStack(spacing: 10) {
                Button("Connect OpenAI Account") {
                    codex.startLogin()
                }
                .buttonStyle(.borderedProminent)
                Button("Refresh") {
                    codex.refreshAccount()
                }
            }
        }
    }

    private var statusIcon: String {
        switch codex.account {
        case .signedIn: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .signedOut: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch codex.account {
        case .signedIn: .green
        case .pending: .orange
        case .signedOut, .unknown: .secondary
        }
    }
}

#if DEBUG
/// QA-only inputs: recorded-trace replay and the mock pose worker. Hidden from release builds.
private struct DeveloperSection: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel

    var body: some View {
        SidebarSettingsSection(title: "Developer") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recorded run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Recorded run", selection: selectedRecordedRunBinding) {
                    ForEach(model.availableRecordedRuns) { run in
                        Text(run.displayName).tag(Optional(run.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard let id = model.selectedRecordedRunID else { return }
                    _ = model.runRecordedRun(id: id)
                } label: {
                    Label("Run recorded sample", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .disabled(model.selectedRecordedRunID == nil)

                Button {
                    model.runMockWorkerProvider()
                } label: {
                    Label("Run mock worker", systemImage: "cpu")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)

                Button {
                    model.preflightMockWorker()
                } label: {
                    Label("Check mock worker", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var selectedRecordedRunBinding: Binding<String?> {
        Binding {
            model.selectedRecordedRunID
        } set: { selectedID in
            guard let selectedID else { return }
            _ = model.runRecordedRun(id: selectedID)
        }
    }
}
#endif

// MARK: - Chat (right panel)

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var rawText: String
    var regimen: [RegimenResult] = []
    var memoryArtifacts: [KGMemoryChatArtifact] = []
    var coachActionArtifacts: [CoachActionResult] = []

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        rawText: String? = nil,
        regimen: [RegimenResult] = [],
        memoryArtifacts: [KGMemoryChatArtifact] = [],
        coachActionArtifacts: [CoachActionResult] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.rawText = rawText ?? text
        self.regimen = regimen
        self.memoryArtifacts = memoryArtifacts
        self.coachActionArtifacts = coachActionArtifacts
    }
}

/// UI-shell chat model: the transcript and composer are real; the responder is a
/// placeholder until a coaching brain (local or Claude) is wired in.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var isResponding = false

    weak var codex: CodexAppServerClient?
    weak var memoryStore: KGMemoryStore?
    var coachActionDispatcher: CoachActionDispatcher?

    var canSend: Bool {
        !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""

        guard let codex else {
            messages.append(ChatMessage(role: .assistant,
                text: "The coach isn't connected. Make sure Codex is available and you're signed in under Settings → OpenAI."))
            return
        }

        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)
        let replyID = reply.id
        isResponding = true

        let codexInput = promptForCodex(userText: text)
        codex.startTurn(text: codexInput, onDelta: { [weak self] delta in
            self?.append(delta, to: replyID)
        }, onComplete: { [weak self] in
            self?.finish(replyID, sourceUserText: text)
        }, onError: { [weak self] message in
            self?.setError(message, on: replyID)
        })
    }

    func send(_ prompt: String) {
        draft = prompt
        send()
    }

    func resetSession() {
        codex?.resetChatSession()
        messages.removeAll()
        draft = ""
        isResponding = false
    }

    func requestWorkoutDebrief(for report: WorkoutCompletionReport) {
        guard !isResponding else { return }

        let visibleRequest = report.scope == .routine
            ? "Review my routine results."
            : "Review my exercise results."
        messages.append(ChatMessage(role: .user, text: visibleRequest))

        guard let codex else {
            messages.append(ChatMessage(
                role: .assistant,
                text: "Workout complete: \(report.finalProgressText). Connect Future Coach for a coaching debrief."
            ))
            return
        }

        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)
        let replyID = reply.id
        isResponding = true

        codex.startTurn(text: WorkoutDebriefPrompt.makePrompt(for: report), onDelta: { [weak self] delta in
            self?.append(delta, to: replyID)
        }, onComplete: { [weak self] in
            self?.finish(replyID, sourceUserText: visibleRequest)
        }, onError: { [weak self] message in
            self?.setError(message, on: replyID)
        })
    }

    func appendCompletedAssistantResponse(_ rawText: String, sourceUserText: String) {
        let reply = ChatMessage(role: .assistant, text: rawText)
        messages.append(reply)
        finish(reply.id, sourceUserText: sourceUserText)
    }

    private func append(_ text: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].rawText += text
        messages[idx].text = ChatStreamingDisplayFilter.displayText(for: messages[idx].rawText)
        messages[idx].regimen = RegimenBlockParser.parse(message: messages[idx].rawText)
    }

    private func finish(_ id: UUID, sourceUserText: String) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let rawAssistantText = messages[idx].rawText
        if rawAssistantText.isEmpty { messages[idx].rawText = "(No response.)" }
        messages[idx].regimen = RegimenBlockParser.parse(message: rawAssistantText)
        messages[idx].coachActionArtifacts = CoachActionParser.parse(message: rawAssistantText).map { action in
            if let coachActionDispatcher {
                return coachActionDispatcher.apply(action)
            }
            return CoachActionResult(
                status: .failed,
                title: "Coach action unavailable",
                detail: "The app action dispatcher is not ready.",
                action: action
            )
        }
        messages[idx].memoryArtifacts = KGMemoryChatBridge.applyProposals(
            in: rawAssistantText,
            sourceUserText: sourceUserText,
            store: memoryStore
        )
        let visibleText = ChatStreamingDisplayFilter.displayText(for: rawAssistantText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        messages[idx].text = visibleText.isEmpty ? fallbackAssistantText(for: messages[idx]) : visibleText
    }

    private func setError(_ message: String, on id: UUID) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let prefix = messages[idx].text.isEmpty ? "" : "\n\n"
        messages[idx].text += "\(prefix)⚠️ \(message)"
    }

    private func fallbackAssistantText(for message: ChatMessage) -> String {
        if !message.regimen.isEmpty { return "Added a routine card." }
        if !message.coachActionArtifacts.isEmpty { return "Updated the exercise view." }
        if !message.memoryArtifacts.isEmpty { return "Updated your memories." }
        return "(No response.)"
    }

    private func promptForCodex(userText: String) -> String {
        guard let context = KGMemoryChatBridge.coachContext(from: memoryStore) else {
            return userText
        }
        return """
        \(userText)

        \(context)
        """
    }
}

private struct ChatPanel: View {
    @EnvironmentObject private var chat: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.45)

            transcript

            ChatComposer()
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.6),
                        Color(nsColor: .windowBackgroundColor).opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        ChatEmptyState()
                            .padding(.top, 14)
                    } else {
                        ForEach(chat.messages) { message in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                                if message.shouldShowBubble {
                                    ChatBubble(message: message)
                                }
                                ForEach(Array(message.regimen.enumerated()), id: \.offset) { _, result in
                                    RegimenCard(result: result)
                                }
                                ForEach(message.memoryArtifacts) { artifact in
                                    ChatMemoryArtifactCard(artifact: artifact)
                                }
                                ForEach(message.coachActionArtifacts) { artifact in
                                    ChatCoachActionCard(artifact: artifact)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last?.id {
                    withAnimation(.smooth) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}

private struct ChatMemoryArtifactCard: View {
    let artifact: KGMemoryChatArtifact

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: artifact.status == .saved ? "brain.head.profile.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(artifact.status == .saved ? .pink : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.title)
                    .font(.caption.weight(.semibold))
                Text(artifact.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.pink.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.pink.opacity(0.16), lineWidth: 1)
                )
        )
        .frame(maxWidth: 250, alignment: .leading)
    }
}

private struct ChatCoachActionCard: View {
    let artifact: CoachActionResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: artifact.status == .succeeded ? "sparkles.tv.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(artifact.status == .succeeded ? .mint : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.title)
                    .font(.caption.weight(.semibold))
                Text(artifact.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.mint.opacity(artifact.status == .succeeded ? 0.08 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke((artifact.status == .succeeded ? Color.mint : Color.orange).opacity(0.16), lineWidth: 1)
                )
        )
        .frame(maxWidth: 250, alignment: .leading)
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var chat: ChatViewModel
    @EnvironmentObject private var codex: CodexAppServerClient

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.07, blue: 0.09),
                                Color(red: 0.08, green: 0.13, blue: 0.12),
                                Color(red: 0.03, green: 0.04, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                BrandLogoMark()
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .teal.opacity(0.18), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Future Coach")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                chat.resetSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset chat session")
            .help("Reset chat session")

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        if codex.account != .signedIn { return "Sign in via Future Coach ▸ Settings" }
        switch codex.state {
        case .idle: return "Idle"
        case .starting: return "Connecting to Codex…"
        case .ready: return "Your momentum starts here."
        case .failed(let message): return message
        }
    }

    private var statusColor: Color {
        switch codex.state {
        case .ready: return codex.account == .signedIn ? .green : .orange
        case .failed: return .red
        default: return .orange
        }
    }
}

private struct ChatEmptyState: View {
    @EnvironmentObject private var chat: ChatViewModel

    private let starters = [
        ("Make my bodyweight lower body routine", "figure.strengthtraining.functional"),
        ("Show me how to workout my core", "target"),
        ("How's my squat form?", "figure.strengthtraining.functional"),
        ("How many reps should I do?", "repeat"),
        ("Give me a quick warm-up", "flame")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                BrandLogoMark()
                    .frame(width: 18, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask your coach")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Questions about form, reps, and your session will live here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(starters, id: \.0) { title, icon in
                    Button {
                        chat.send(title)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.075), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem
        case orderedListItem(number: String)
    }

    let kind: Kind
    let text: String
}

enum ChatMarkdownRenderer {
    static func blocks(for text: String) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let heading = parseHeading(trimmed) {
                blocks.append(ChatMarkdownBlock(kind: .heading(level: heading.level), text: heading.text))
            } else if let unordered = parseUnorderedListItem(trimmed) {
                blocks.append(ChatMarkdownBlock(kind: .unorderedListItem, text: unordered))
            } else if let ordered = parseOrderedListItem(trimmed) {
                blocks.append(ChatMarkdownBlock(kind: .orderedListItem(number: ordered.number), text: ordered.text))
            } else {
                blocks.append(ChatMarkdownBlock(kind: .paragraph, text: trimmed))
            }
        }

        return blocks
    }

    static func attributedString(for text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return AttributedString(text)
        }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first?.isWhitespace == true else {
            return nil
        }

        let text = line
            .dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
        return text.isEmpty ? nil : (level, text)
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+",
              line.dropFirst().first?.isWhitespace == true else {
            return nil
        }

        let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func parseOrderedListItem(_ line: String) -> (number: String, text: String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }

        let afterDigits = line.dropFirst(digits.count)
        guard let marker = afterDigits.first, marker == "." || marker == ")",
              afterDigits.dropFirst().first?.isWhitespace == true else {
            return nil
        }

        let text = afterDigits.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (String(digits), text)
    }
}

private struct ChatMarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ChatMarkdownRenderer.blocks(for: text).enumerated()), id: \.offset) { _, block in
                ChatMarkdownBlockView(block: block)
            }
        }
    }
}

private struct ChatMarkdownBlockView: View {
    let block: ChatMarkdownBlock

    private let bodyFont = Font.system(size: 13.5, weight: .regular, design: .rounded)

    var body: some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.text)
                .font(bodyFont)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level):
            inlineText(block.text)
                .font(headingFont(for: level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case .unorderedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .frame(width: 12, alignment: .trailing)
                inlineText(block.text)
                    .font(bodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .orderedListItem(let number):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 22, alignment: .trailing)
                inlineText(block.text)
                    .font(bodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inlineText(_ text: String) -> Text {
        Text(ChatMarkdownRenderer.attributedString(for: text))
    }

    private func headingFont(for level: Int) -> Font {
        level <= 2
            ? .system(size: 15, weight: .semibold, design: .rounded)
            : .system(size: 14, weight: .semibold, design: .rounded)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 28)
                bubble
            } else {
                ChatAvatar()
                bubble
                Spacer(minLength: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubble: some View {
        ChatMarkdownText(text: message.text)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .frame(maxWidth: 250, alignment: isUser ? .trailing : .leading)
    }
}

private struct ChatAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.08))
            BrandLogoMark()
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        }
        .frame(width: 24, height: 24)
        .padding(.top, 1)
    }
}

private struct ChatComposer: View {
    @EnvironmentObject private var chat: ChatViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Message the coach", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .lineLimit(1...6)
                .padding(.vertical, 5)
                .onSubmit { chat.send() }

            Button {
                chat.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(chat.canSend ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .help("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.11), lineWidth: 1)
                )
        )
    }
}

// MARK: - Reusable atoms

private struct HeroStat: Identifiable {
    let label: String
    let value: String
    var detail: String?
    let systemImage: String
    var minWidth: CGFloat = 76

    var id: String { label }
}

private struct StatTile: View {
    var stat: HeroStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: stat.systemImage)
                    .imageScale(.small)
                    .foregroundStyle(.cyan)
                Text(stat.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(stat.value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail = stat.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minWidth: stat.minWidth, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(.black.opacity(0.22)), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct Chip: View {
    var systemImage: String
    var text: String
    var tint: Color
    var foreground: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(foreground ?? tint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground ?? .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
    }
}
