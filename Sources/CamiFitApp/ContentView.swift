import CamiFitEngine
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
}

struct ContentView: View {
    @EnvironmentObject private var onboarding: OnboardingCoordinator
    @EnvironmentObject private var settingsSelection: AppSettingsSelection
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    @ObservedObject var liveSession: LiveSession
    @ObservedObject var codex: CodexAppServerClient
    @AppStorage(OnboardingCoordinator.completedStorageKey) private var didCompleteOnboarding = false
    @AppStorage(OnboardingCoordinator.completedVersionStorageKey) private var completedOnboardingVersion = 0
    @StateObject private var routineRunner: RoutineRunner
    @StateObject private var chat = ChatViewModel()
    @StateObject private var exerciseMode = ExerciseModeController()
    @StateObject private var memoryStore = KGMemoryStore()
    @StateObject private var routineLibrary = RoutineLibraryStore()
    @State private var inspectorState = AppInspectorState()
    @State private var lastDebriefedReport: WorkoutCompletionReport?
    @State private var presentsInitialOnboarding = false
    @State private var didBootstrapLaunch = false
    @State private var didPresentInitialOnboarding = false

    init(viewModel: AppExerciseSessionViewModel, liveSession: LiveSession, codex: CodexAppServerClient) {
        self.viewModel = viewModel
        self.liveSession = liveSession
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
                        Button {
                            onboarding.showTour()
                        } label: {
                            Label("Tour", systemImage: "questionmark.circle")
                        }
                        .help("Show the Momentum feature tour")
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
                            ChatPanel { operationID in
                                withAnimation(.smooth) {
                                    inspectorState.showMemory(focusedOperationID: operationID)
                                }
                            }
                        case .memory:
                            KGMemoryPanel(
                                store: memoryStore,
                                focusedOperationID: inspectorState.focusedMemoryOperationID
                            )
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 380)
                }
        }
        .navigationTitle(ProductBrand.shortName)
        .navigationSubtitle("Your Future Coach")
        .sheet(isPresented: onboardingSheetBinding, onDismiss: completeOnboardingIfNeeded) {
            OnboardingFlowView(onFinish: {
                markOnboardingCompleted()
                presentsInitialOnboarding = false
                onboarding.dismiss()
            })
        }
        .environmentObject(viewModel)
        .environmentObject(liveSession)
        .environmentObject(chat)
        .environmentObject(codex)
        .environmentObject(routineLibrary)
        .environmentObject(routineRunner)
        .environmentObject(exerciseMode)
        .onAppear {
            bootstrapLaunchIfNeeded()
        }
        .task {
            bootstrapLaunchIfNeeded()
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
            presentCameraSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, liveSession.shouldRefreshCameraAccessAfterSettings else { return }
            liveSession.refreshCameraAccessAfterSettings()
            routineRunner.updateCameraReadiness(liveSession.camera.readiness)
        }
    }

    private var hasCompletedCurrentOnboarding: Bool {
        didCompleteOnboarding && completedOnboardingVersion >= OnboardingCoordinator.currentVersion
    }

    private var onboardingSheetBinding: Binding<Bool> {
        Binding {
            onboarding.isPresented || presentsInitialOnboarding
        } set: { isPresented in
            if isPresented {
                presentsInitialOnboarding = true
            } else {
                presentsInitialOnboarding = false
                onboarding.dismiss()
            }
        }
    }

    private func bootstrapLaunchIfNeeded() {
        guard !didBootstrapLaunch else { return }
        didBootstrapLaunch = true

        viewModel.loadAvailablePresets()
        if let guideExerciseID = CamiFitLaunchEnvironment.guideExerciseID {
            try? viewModel.selectPreset(id: guideExerciseID)
            try? routineRunner.startExercise(exerciseID: guideExerciseID, mode: .guide)
            markOnboardingCompleted()
            presentsInitialOnboarding = false
            onboarding.dismiss()
        }
        viewModel.loadRecordedRuns()
        routineLibrary.load()
        presentInitialOnboardingIfNeeded()
        liveSession.refreshCameras()
        if CamiFitLaunchEnvironment.guideExerciseID == nil {
            if liveSession.availableCameras.isEmpty {
                liveSession.requestCameraSettingsIfNoCameras()
            } else {
                let permissionDelay: TimeInterval = hasCompletedCurrentOnboarding ? 0.1 : 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + permissionDelay) {
                    liveSession.requestCameraPermissionOnLaunch()
                }
            }
        }
        chat.codex = codex
        chat.memoryStore = memoryStore
        chat.assignmentWorkoutPlanner = AssignmentWorkoutPlanner()
        chat.assignmentCopilotProvider = AssignmentCopilotProvider()
        let settingsSelection = settingsSelection
        let openSettings = openSettings
        let codex = codex
        chat.onOpenAIAccountRequired = {
            settingsSelection.promptForOpenAIChatSignIn()
            codex.refreshAccount()
            openSettings()
        }
        chat.coachActionDispatcher = CoachActionDispatcher(
            viewModel: viewModel,
            routineRunner: routineRunner,
            modeController: exerciseMode
        )
        codex.start()
        memoryStore.load()
        routineRunner.updateCameraReadiness(liveSession.camera.readiness)
        routineRunner.updatePoseReadiness(liveSession.poseReadiness)
    }

    private func presentInitialOnboardingIfNeeded() {
        guard !didPresentInitialOnboarding,
              CamiFitLaunchEnvironment.guideExerciseID == nil,
              !hasCompletedCurrentOnboarding
        else { return }

        didPresentInitialOnboarding = true
        presentsInitialOnboarding = true
    }

    private func markOnboardingCompleted() {
        didCompleteOnboarding = true
        completedOnboardingVersion = OnboardingCoordinator.currentVersion
    }

    private func completeOnboardingIfNeeded() {
        if !hasCompletedCurrentOnboarding {
            markOnboardingCompleted()
        }
    }

    private func presentCameraSettings() {
        liveSession.refreshCameras()
        settingsSelection.selectedTab = .camera
        openSettings()
    }
}

enum AppInspectorMode: Equatable {
    case coach
    case memory
}

struct AppInspectorState: Equatable {
    var isPresented = true
    var mode: AppInspectorMode = .coach
    var focusedMemoryOperationID: String?

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
        focusedMemoryOperationID = nil
    }

    mutating func showMemory(focusedOperationID: String? = nil) {
        mode = .memory
        isPresented = true
        focusedMemoryOperationID = focusedOperationID
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
    @StateObject private var feedbackSpeaker = WorkoutFeedbackSpeaker()
    @AppStorage(WorkoutFeedbackSpeaker.audioModeStorageKey) private var feedbackAudioModeRaw = WorkoutFeedbackAudioMode.spoken.rawValue
    @State private var feedMode: HeroFeedMode = .avatarGuide
    @State private var showsSkeletonOverlay = true
    @State private var feedbackEvent: WorkoutFeedbackEvent?
    @State private var feedbackPresentation: CGFloat = 0
    @State private var feedbackHaloExpansion: CGFloat = 0
    @State private var feedbackDismissGeneration = 0
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
                                    enterCameraMode()
                                } else {
                                    exitCameraMode()
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

            if let feedbackEvent {
                HeroWorkoutFeedbackOverlay(
                    event: feedbackEvent,
                    presentation: feedbackPresentation,
                    haloExpansion: feedbackHaloExpansion
                )
                    .id(feedbackEvent.id)
                    .transition(.opacity)
                    .zIndex(4)
            }

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
        .onChange(of: feedMode) { _, _ in
            syncLivePipeline(for: routineRunner.phase)
        }
        .onReceive(model.$lastFeedbackEvent) { event in
            guard let event else { return }
            presentFeedback(event)
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
            guard !routineRunner.phase.needsCamera else { return }
            if feedMode == .tracking {
                ensureStandaloneLiveCamera()
            } else {
                withAnimation(.smooth) {
                    feedMode = .avatarGuide
                }
            }
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
        switch HeroCameraPipelinePolicy.action(
            feedMode: feedMode,
            phase: phase,
            liveRunning: liveSession.running,
            isLiveCamera: liveSession.isLiveCamera,
            routesPoseFramesExternally: liveSession.routesPoseFramesExternally
        ) {
        case .none:
            break
        case .stop:
            liveSession.stop()
            if phase.usesGuide || feedMode == .avatarGuide {
                feedMode = .avatarGuide
            }
        case .startRoutine:
            if feedMode != .tracking {
                feedMode = .tracking
            }
            ensureRoutineLiveCamera()
        case .startStandalone:
            ensureStandaloneLiveCamera()
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

    private func ensureStandaloneLiveCamera() {
        if liveSession.running, liveSession.isLiveCamera, !liveSession.routesPoseFramesExternally {
            return
        }
        liveSession.stop()
        liveSession.start(viewModel: model)
    }

    private func enterCameraMode() {
        feedMode = .tracking
        syncLivePipeline(for: routineRunner.phase)
    }

    private func exitCameraMode() {
        feedMode = .avatarGuide
        if !routineRunner.phase.needsCamera {
            liveSession.stop()
        }
        model.resetLiveSession()
    }

    private func presentFeedback(_ event: WorkoutFeedbackEvent) {
        feedbackDismissGeneration += 1
        let generation = feedbackDismissGeneration

        triggerRepPulse()
        feedbackSpeaker.play(event, modeRawValue: feedbackAudioModeRaw)
        feedbackPresentation = 0
        feedbackHaloExpansion = 0
        feedbackEvent = event

        withAnimation(.spring(response: 0.42, dampingFraction: 0.84, blendDuration: 0.08)) {
            feedbackPresentation = 1
        }
        withAnimation(.easeOut(duration: 1.45)) {
            feedbackHaloExpansion = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_450_000_000)
            guard generation == feedbackDismissGeneration else { return }
            withAnimation(.easeInOut(duration: 0.62)) {
                feedbackPresentation = 0
            }
            try? await Task.sleep(nanoseconds: 640_000_000)
            guard generation == feedbackDismissGeneration else { return }
            feedbackHaloExpansion = 0
            feedbackEvent = nil
        }
    }

    private func triggerRepPulse() {
        repPulseGeneration += 1
        let generation = repPulseGeneration

        withAnimation(.easeOut(duration: 0.28)) {
            repPulseStrength = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard generation == repPulseGeneration else { return }
            withAnimation(.easeOut(duration: 1.15)) {
                repPulseStrength = 0
            }
        }
    }

    private func applyExerciseModeRequest(_ request: ExerciseModeRequest) {
        guard model.state.selectedExerciseID == request.exerciseID else { return }

        switch request.mode {
        case .guide:
            formCheck.cancel()
            exitCameraMode()
        case .camera:
            formCheck.cancel()
            enterCameraMode()
        case .matchForm:
            formCheck.begin(current: model.state)
            enterCameraMode()
        }
    }
}

enum HeroFeedMode: Equatable {
    case tracking
    case avatarGuide
}

enum HeroCameraPipelineAction: Equatable {
    case none
    case stop
    case startStandalone
    case startRoutine
}

enum HeroCameraPipelinePolicy {
    static func action(
        feedMode: HeroFeedMode,
        phase: RoutineRunPhase,
        liveRunning: Bool,
        isLiveCamera: Bool,
        routesPoseFramesExternally: Bool
    ) -> HeroCameraPipelineAction {
        if phase.usesGuide {
            return liveRunning ? .stop : .none
        }
        if phase.needsCamera {
            return liveRunning && isLiveCamera && routesPoseFramesExternally ? .none : .startRoutine
        }
        if case .complete = phase {
            return liveRunning ? .stop : .none
        }
        if case .failed = phase {
            return liveRunning ? .stop : .none
        }
        if feedMode == .tracking {
            return liveRunning && isLiveCamera && !routesPoseFramesExternally ? .none : .startStandalone
        }
        return liveRunning ? .stop : .none
    }
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
                ZStack {
                    CameraPreview(session: liveSession.camera.session, mirrored: false)
                        .background(Color.black)
                    if showsSkeletonOverlay {
                        LivePoseOverlay(
                            state: model.latestPoseOverlayState,
                            sourceSize: liveSession.sourceSize,
                            mirrored: false
                        )
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(x: -1, y: 1)
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
                    sourceSize: liveSession.sourceSize,
                    mirrored: liveSession.running && liveSession.isLiveCamera
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
            Text("Camera mode starts tracking automatically when it is active.")
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

private struct HeroWorkoutFeedbackOverlay: View {
    let event: WorkoutFeedbackEvent
    let presentation: CGFloat
    let haloExpansion: CGFloat

    private var clampedPresentation: CGFloat {
        min(max(presentation, 0), 1)
    }

    private var clampedHaloExpansion: CGFloat {
        min(max(haloExpansion, 0), 1)
    }

    private var tint: Color {
        switch event.emphasis {
        case .counted:
            return .yellow
        case .clean:
            return .green
        case .complete:
            return .cyan
        }
    }

    private var symbolName: String {
        event.emphasis == .complete ? "checkmark.circle.fill" : "checkmark"
    }

    private var confirmationDiameter: CGFloat {
        event.kind == .holdComplete ? 336 : 320
    }

    private var contentWidth: CGFloat {
        confirmationDiameter - 72
    }

    private var primaryFontSize: CGFloat {
        event.kind == .holdComplete ? 82 : 118
    }

    var body: some View {
        let presentation = clampedPresentation
        let haloExpansion = clampedHaloExpansion
        let haloOpacity = Double(presentation) * Double(1 - (haloExpansion * 0.48))
        let contentScale = 0.94 + (0.06 * presentation)
        let contentLift = 16 * (1 - presentation)

        ZStack {
            tint.opacity(0.12 * Double(presentation))
                .blendMode(.screen)

            Circle()
                .fill(tint.opacity(0.10 * Double(presentation)))
                .frame(width: confirmationDiameter, height: confirmationDiameter)
                .scaleEffect(0.96 + (0.04 * presentation))
                .blur(radius: 14)

            Circle()
                .fill(.black.opacity(0.20 * Double(presentation)))
                .frame(width: confirmationDiameter, height: confirmationDiameter)

            Circle()
                .stroke(tint.opacity(0.46 * haloOpacity), lineWidth: 3)
                .frame(width: confirmationDiameter, height: confirmationDiameter)
                .scaleEffect(0.96 + (0.14 * haloExpansion))
                .blur(radius: 0.4)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.28 * Double(presentation)))
                        .frame(width: 64, height: 64)

                    Image(systemName: symbolName)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(tint)
                        .shadow(color: tint.opacity(0.72), radius: 16)
                }

                Text(event.primaryText)
                    .font(.system(size: primaryFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())

                Text(event.detailText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: contentWidth)
            .frame(width: confirmationDiameter, height: confirmationDiameter)
            .offset(y: contentLift)
            .scaleEffect(contentScale)
            .opacity(Double(presentation))
            .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.primaryText), \(event.detailText)")
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
    private var showsRecordingControls: Bool {
        ProcessInfo.processInfo.environment["CAMIFIT_SHOW_RECORDING_CONTROLS"] == "1"
    }
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
                            feedMode = .avatarGuide
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

                    if liveActive && showsRecordingControls {
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
    case exercises
    case routines

    var title: String {
        switch self {
        case .exercises: "Exercises"
        case .routines: "Routines"
        }
    }

    var systemImage: String {
        switch self {
        case .exercises: "figure.strengthtraining.functional"
        case .routines: "list.bullet.rectangle"
        }
    }
}

private struct SessionSidebar: View {
    @SceneStorage("camifit.sidebar.tab") private var selectedTabRaw = SidebarTab.exercises.rawValue

    private var selectedTab: SidebarTab {
        SidebarTab(rawValue: selectedTabRaw) ?? .exercises
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
                case .exercises:
                    ExerciseLibrarySidebar()
                case .routines:
                    RoutineLibrarySidebar()
                }
            }
        }
        .navigationTitle(selectedTab.title)
    }

    private var selectedTabBinding: Binding<SidebarTab> {
        Binding {
            selectedTab
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
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
    @State private var focusedItem: ExerciseLibraryFocus?
    @State private var assessmentExercises: [AssessmentExerciseSummary] = []
    @State private var assessmentCatalogError: String?

    var body: some View {
        SidebarDrillInPane(
            isShowingDetail: focusedItem != nil,
            backTitle: "Exercises",
            onBack: { focusedItem = nil }
        ) {
            exerciseList
        } detail: {
            if let focusedPreset {
                ExerciseDetailPanel(preset: focusedPreset)
            } else if let focusedAssessmentExercise {
                AssessmentExerciseDetailPanel(exercise: focusedAssessmentExercise)
            } else {
                Text("Exercise unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            model.loadAvailablePresets()
            loadAssessmentExercises()
        }
    }

    private var focusedPreset: AppPresetSummary? {
        guard case let .preset(id)? = focusedItem else { return nil }
        return model.availablePresets.first { $0.id == id }
    }

    private var focusedAssessmentExercise: AssessmentExerciseSummary? {
        guard case let .assessment(id)? = focusedItem else { return nil }
        return assessmentExercises.first { $0.id == id }
    }

    private var exerciseList: some View {
        List {
            Section("Trackable presets") {
                if guideReadyPresets.isEmpty {
                    Text("No trackable presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(guideReadyPresets) { preset in
                    Button {
                        open(preset)
                    } label: {
                        ExerciseSidebarRow(preset: preset, isSelected: preset.id == model.state.selectedExerciseID)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                }
            }

            Section("Assessment catalog") {
                if let assessmentCatalogError {
                    Text(assessmentCatalogError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if assessmentExercises.isEmpty {
                    Text("No assessment exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(assessmentExercises) { exercise in
                    Button {
                        open(exercise)
                    } label: {
                        AssessmentExerciseSidebarRow(
                            exercise: exercise,
                            isFocused: focusedItem == .assessment(exercise.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 8)
    }

    private var guideReadyPresets: [AppPresetSummary] {
        model.availablePresets.filter { $0.trackingReadiness == .guideReady }
    }

    private func open(_ preset: AppPresetSummary) {
        if preset.trackingReadiness == .guideReady {
            select(preset)
        }
        focusedItem = .preset(preset.id)
    }

    private func open(_ exercise: AssessmentExerciseSummary) {
        focusedItem = .assessment(exercise.id)
    }

    private func select(_ preset: AppPresetSummary) {
        withAnimation(.smooth(duration: 0.30)) {
            routineRunner.cancel()
            try? model.selectPreset(id: preset.id)
        }
    }

    private func loadAssessmentExercises() {
        guard assessmentExercises.isEmpty else { return }
        do {
            assessmentExercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
            assessmentCatalogError = nil
        } catch {
            assessmentCatalogError = "Assessment catalog unavailable"
        }
    }
}

private enum ExerciseLibraryFocus: Equatable {
    case preset(String)
    case assessment(String)
}

private struct ExerciseSidebarRow: View {
    let preset: AppPresetSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SidebarRowGlyph(
                systemImage: preset.kind == .reps ? "repeat" : "timer",
                tint: preset.trackingReadiness == .guideReady ? (preset.kind == .reps ? .cyan : .blue) : .orange,
                isSelected: isSelected
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(preset.trackingReadiness == .guideReady ? (preset.kind == .reps ? "Counts reps" : "Timed hold") : preset.trackingReadiness.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(preset.trackingReadiness == .guideReady ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
    }
}

private struct AssessmentExerciseSidebarRow: View {
    let exercise: AssessmentExerciseSummary
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            SidebarRowGlyph(
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .orange,
                isSelected: isFocused
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(exercise.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? Color.orange.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? Color.orange.opacity(0.18) : Color.clear, lineWidth: 1)
        )
    }
}

private struct SidebarRowGlyph: View {
    let systemImage: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? tint : Color.secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.18 : 0.10))
            )
    }
}

private struct AssessmentExerciseDetailPanel: View {
    let exercise: AssessmentExerciseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SidebarMetricGrid(metrics: [
                SidebarMetric(label: "Tracking", value: exercise.statusText, systemImage: "checklist.unchecked"),
                SidebarMetric(label: "Measures", value: exercise.trackingCoverage.status.measurementSupportText, systemImage: "ruler"),
                SidebarMetric(label: "Maps To", value: exercise.mappedPresetText, systemImage: "figure.walk.motion"),
                SidebarMetric(label: "Mode", value: exercise.modeText, systemImage: "slider.horizontal.3"),
                SidebarMetric(label: "Source", value: sourceText, systemImage: "number"),
                SidebarMetric(label: "Catalog", value: "Assessment KG", systemImage: "point.3.connected.trianglepath.dotted")
            ])

            AssessmentExerciseTagSection(title: "Tracking Notes", systemImage: "info.circle", items: exercise.trackingCoverage.reasons)
            AssessmentExerciseTagSection(title: "Equipment", systemImage: "dumbbell", items: exercise.equipmentNames)
            AssessmentExerciseTagSection(title: "Movement", systemImage: "figure.run", items: exercise.movementPatternNames)
            AssessmentExerciseTagSection(title: "Muscles", systemImage: "figure.strengthtraining.functional", items: exercise.muscleGroupNames)
            AssessmentExerciseTagSection(title: "Stress Regions", systemImage: "waveform.path.ecg", items: exercise.bodyRegionNames)
            AssessmentExerciseTagSection(title: "Family", systemImage: "square.stack.3d.up", items: exercise.familyNames)
        }
        .padding(14)
    }

    private var sourceText: String {
        guard let sourceExerciseID = exercise.sourceExerciseID else { return "Synthetic" }
        return String(sourceExerciseID.prefix(8))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(exercise.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
    }
}

private struct AssessmentExerciseTagSection: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        SidebarDetailSection(title: title) {
            if items.isEmpty {
                Text("None recorded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        Label(item, systemImage: systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
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
                Text(preset.trackingReadiness == .guideReady ? (preset.kind == .reps ? "Counts reps" : "Timed hold") : preset.trackingReadiness.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(preset.trackingReadiness == .guideReady ? Color.secondary : Color.orange)
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
                        RoutineSidebarRow(
                            routine: routine,
                            summary: summary(for: routine),
                            isSelected: routine.id == routineLibrary.selectedRoutineID
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 8)
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SidebarRowGlyph(
                systemImage: "list.bullet.rectangle",
                tint: summary.isRunnable ? .green : .orange,
                isSelected: isSelected
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(summary.compactDetailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
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
                SidebarMetric(label: "Status", value: statusText(for: summary), systemImage: summary.isRunnable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            ])

            Button {
                startGuidedRoutine()
            } label: {
                Label(summary.availabilityText == nil ? "Start Routine" : "Start Guided Blocks", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!isRunnable)

            if let availabilityText = summary.availabilityText {
                Text(availabilityText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private var isRunnable: Bool {
        guard let guidedRoutine = guidedRoutine(startingAt: 0) else { return false }
        return (try? compiler().compile(guidedRoutine)) != nil
    }

    private func statusText(for summary: RoutinePresentationSummary) -> String {
        guard summary.isRunnable else { return "Unavailable" }
        return summary.availabilityText == nil ? "Ready" : "Guided subset"
    }

    private func display(for block: RoutineBlock) -> RoutineExerciseDisplay {
        if let unavailableText = block.guidanceUnavailableText {
            return unavailableDisplay(for: block, message: unavailableText)
        }

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
            guard let guidedRoutine = guidedRoutine(startingAt: index) else {
                actionError = "No guided exercise is available from here yet."
                return
            }
            try routineRunner.start(guidedRoutine)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func startGuidedRoutine() {
        startFrom(0)
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
        case let .catalog(_, name):
            return name
        }
    }

    private func guidedRoutine(startingAt index: Int) -> WorkoutRoutine? {
        let routineCompiler = compiler()
        let guidedBlocks = routine.blocks.enumerated()
            .filter { pair in
                pair.offset >= index && isCompilerGatedGuideAvailable(
                    for: pair.element,
                    compiler: routineCompiler
                )
            }
            .map { $0.element }
        guard !guidedBlocks.isEmpty else { return nil }
        return WorkoutRoutine(
            schemaVersion: routine.schemaVersion,
            artifactType: routine.artifactType,
            id: "\(routine.id)-guided-from-\(index + 1)",
            name: routine.name,
            description: routine.description,
            blocks: guidedBlocks
        )
    }

    private func isCompilerGatedGuideAvailable(
        for block: RoutineBlock,
        compiler routineCompiler: RoutineCompiler
    ) -> Bool {
        guard block.isGuideAvailable else { return false }
        let single = WorkoutRoutine(
            id: "\(routine.id)-block-check",
            name: routine.name,
            blocks: [block]
        )
        return (try? routineCompiler.compile(single)) != nil
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

// MARK: - Settings (Cmd+,)

struct CamiFitSettingsView: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var liveSession: LiveSession
    @EnvironmentObject private var codex: CodexAppServerClient
    @EnvironmentObject private var settingsSelection: AppSettingsSelection
    @AppStorage(WorkoutFeedbackSpeaker.audioModeStorageKey) private var feedbackAudioModeRaw = WorkoutFeedbackAudioMode.spoken.rawValue

    var body: some View {
        TabView(selection: $settingsSelection.selectedTab) {
            accountPane
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppSettingsTab.account)

            feedbackPane
                .tabItem { Label("Feedback", systemImage: "speaker.wave.2") }
                .tag(AppSettingsTab.feedback)

            cameraPane
                .tabItem { Label("Camera", systemImage: "video") }
                .tag(AppSettingsTab.camera)

            #if DEBUG
            developerPane
                .tabItem { Label("Developer", systemImage: "hammer") }
                .tag(AppSettingsTab.developer)
            #endif
        }
        .frame(width: 520, height: 360)
        .scenePadding()
        .onAppear {
            codex.refreshAccount()
            liveSession.refreshCameras()
            model.loadRecordedRuns()
        }
        .onChange(of: codex.account) { _, account in
            if account == .signedIn {
                settingsSelection.clearAccountPrompt()
            }
        }
    }

    private var accountPane: some View {
        Form {
            Section {
                accountPrompt

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
                Text("\(ProductBrand.fullName) signs in with your ChatGPT account through Codex. The coach uses this account for every reply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var feedbackPane: some View {
        Form {
            Section {
                Picker("Audio", selection: feedbackAudioModeBinding) {
                    Text("Spoken").tag(WorkoutFeedbackAudioMode.spoken)
                    Text("Tone").tag(WorkoutFeedbackAudioMode.tone)
                    Text("Off").tag(WorkoutFeedbackAudioMode.off)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Rep Feedback")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var accountPrompt: some View {
        if let prompt = settingsSelection.accountPrompt, codex.account != .signedIn {
            Label {
                Text(prompt)
                    .font(.callout.weight(.semibold))
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.primary)
        }
    }

    private var cameraPane: some View {
        Form {
            Section {
                cameraSelectionPrompt
            }

            Section {
                Picker("Input", selection: $liveSession.selectedCameraID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(liveSession.availableCameras) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
                .onChange(of: liveSession.selectedCameraID) { _, newID in
                    liveSession.camera.setDevice(newID)
                }

                LabeledContent("Status") {
                    Text(liveSession.camera.readiness.displayText)
                        .foregroundStyle(.secondary)
                }

                Button {
                    liveSession.refreshCameras()
                } label: {
                    Label("Refresh Cameras", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Camera")
            } footer: {
                if liveSession.availableCameras.isEmpty {
                    Text("No cameras detected. The app will keep trying automatic camera selection when live tracking starts.")
                } else {
                    Text("Choose the webcam used by Live Camera in the workout view. Automatic lets CamiFit pick the default camera.")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var cameraSelectionPrompt: some View {
        if liveSession.availableCameras.isEmpty {
            Label("Connect a camera, then refresh this list.", systemImage: "video.slash")
                .foregroundStyle(.secondary)
        } else {
            Label("Select the connected camera you want CamiFit to use.", systemImage: "video.badge.checkmark")
        }
    }

    #if DEBUG
    private var developerPane: some View {
        Form {
            Section {
                Picker("Recorded Run", selection: selectedRecordedRunBinding) {
                    ForEach(model.availableRecordedRuns) { run in
                        Text(run.displayName).tag(Optional(run.id))
                    }
                }

                Button {
                    guard let id = model.selectedRecordedRunID else { return }
                    _ = model.runRecordedRun(id: id)
                } label: {
                    Label("Run Recorded Sample", systemImage: "play.rectangle")
                }
                .disabled(model.selectedRecordedRunID == nil)

                Button {
                    model.runMockWorkerProvider()
                } label: {
                    Label("Run Mock Worker", systemImage: "cpu")
                }

                Button {
                    model.preflightMockWorker()
                } label: {
                    Label("Check Mock Worker", systemImage: "stethoscope")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("QA-only inputs for recorded trace replay and mock pose worker checks. These controls are hidden from release builds.")
            }
        }
        .formStyle(.grouped)
    }
    #endif

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

    private var feedbackAudioModeBinding: Binding<WorkoutFeedbackAudioMode> {
        Binding {
            WorkoutFeedbackAudioMode(rawValue: feedbackAudioModeRaw) ?? .spoken
        } set: { mode in
            feedbackAudioModeRaw = mode.rawValue
        }
    }

#if DEBUG
    private var selectedRecordedRunBinding: Binding<String?> {
        Binding {
            model.selectedRecordedRunID
        } set: { selectedID in
            guard let selectedID else { return }
            _ = model.runRecordedRun(id: selectedID)
        }
    }
#endif
}

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
    var kgWorkoutArtifacts: [KGWorkoutChatArtifact] = []
    var copilotArtifacts: [AssignmentCopilotFactCard] = []

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        rawText: String? = nil,
        regimen: [RegimenResult] = [],
        memoryArtifacts: [KGMemoryChatArtifact] = [],
        coachActionArtifacts: [CoachActionResult] = [],
        kgWorkoutArtifacts: [KGWorkoutChatArtifact] = [],
        copilotArtifacts: [AssignmentCopilotFactCard] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.rawText = rawText ?? text
        self.regimen = regimen
        self.memoryArtifacts = memoryArtifacts
        self.coachActionArtifacts = coachActionArtifacts
        self.kgWorkoutArtifacts = kgWorkoutArtifacts
        self.copilotArtifacts = copilotArtifacts
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
    var assignmentWorkoutPlanner: AssignmentWorkoutPlanning?
    var assignmentCopilotProvider: AssignmentCopilotProviding?
    var coachActionDispatcher: CoachActionDispatcher?
    var onOpenAIAccountRequired: (() -> Void)?

    var canSend: Bool {
        !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""

        guard let codex else {
            appendOpenAIAccountRequiredMessage()
            return
        }
        if Self.shouldPromptForOpenAIAccount(codex.account) {
            appendOpenAIAccountRequiredMessage()
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
                text: "Workout complete: \(report.finalProgressText). Connect \(ProductBrand.fullName) for a coaching debrief."
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
        let memoryArtifacts = KGMemoryChatBridge.applyProposals(
            in: rawAssistantText,
            sourceUserText: sourceUserText,
            store: memoryStore
        )
        messages[idx].memoryArtifacts = memoryArtifacts
        let copilotResult = applyCopilotRequests(in: rawAssistantText)
        messages[idx].copilotArtifacts = copilotResult.artifacts
        let workoutResult = applyWorkoutRequests(in: rawAssistantText)
        messages[idx].kgWorkoutArtifacts = workoutResult.artifacts
        messages[idx].regimen = RegimenBlockParser.parse(message: rawAssistantText)
            + workoutResult.artifacts.map { .routine($0.routine) }
        let visibleText = ChatStreamingDisplayFilter.displayText(for: rawAssistantText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleWithErrors = [visibleText, copilotResult.errorText, workoutResult.errorText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        messages[idx].text = visibleWithErrors.isEmpty ? fallbackAssistantText(for: messages[idx]) : visibleWithErrors
    }

    private func applyCopilotRequests(in assistantText: String) -> (artifacts: [AssignmentCopilotFactCard], errorText: String?) {
        let requests = AssignmentCopilotRequestParser.parse(message: assistantText)
        guard !requests.isEmpty else { return ([], nil) }
        guard let assignmentCopilotProvider else {
            return ([], "I understood the member-fact request, but the local graph reader is not available.")
        }

        var artifacts: [AssignmentCopilotFactCard] = []
        var failures: [String] = []
        for request in requests {
            do {
                artifacts.append(try assignmentCopilotProvider.factCard(for: request))
            } catch {
                failures.append("I couldn't read the member facts for that request: \(error).")
            }
        }

        return (artifacts, failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }

    private func applyWorkoutRequests(in assistantText: String) -> (artifacts: [KGWorkoutChatArtifact], errorText: String?) {
        let requests = KGWorkoutRequestParser.parse(message: assistantText)
        guard !requests.isEmpty else { return ([], nil) }
        guard let assignmentWorkoutPlanner else {
            return ([], "I understood the routine request, but the local workout planner is not available.")
        }

        var artifacts: [KGWorkoutChatArtifact] = []
        var failures: [String] = []
        for request in requests {
            do {
                artifacts.append(try assignmentWorkoutPlanner.makeArtifact(request: request))
            } catch {
                failures.append("I couldn't generate that routine from your saved context: \(error).")
            }
        }

        return (artifacts, failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }

    private func setError(_ message: String, on id: UUID) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let prefix = messages[idx].text.isEmpty ? "" : "\n\n"
        messages[idx].text += "\(prefix)⚠️ \(message)"
        if Self.isOpenAIAccountError(message) {
            onOpenAIAccountRequired?()
        }
    }

    private func appendOpenAIAccountRequiredMessage() {
        messages.append(ChatMessage(
            role: .assistant,
            text: "Sign in to OpenAI in Settings to use chat."
        ))
        onOpenAIAccountRequired?()
    }

    private static func isOpenAIAccountError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("401")
            || lowercased.contains("unauthorized")
            || lowercased.contains("not signed in")
            || lowercased.contains("sign in")
            || lowercased.contains("login")
    }

    private static func shouldPromptForOpenAIAccount(_ account: CodexAppServerClient.AccountState) -> Bool {
        switch account {
        case .signedIn, .unknown:
            return false
        case .signedOut, .pending:
            return true
        }
    }

    private func fallbackAssistantText(for message: ChatMessage) -> String {
        if !message.regimen.isEmpty { return "Added a routine card." }
        if !message.kgWorkoutArtifacts.isEmpty { return "Generated a routine." }
        if !message.copilotArtifacts.isEmpty { return "Found graph-backed member facts." }
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
    let onShowMemory: (String?) -> Void

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
                                ForEach(message.kgWorkoutArtifacts) { artifact in
                                    KGWorkoutPlanCard(
                                        artifact: artifact,
                                        onShowMemory: onShowMemory
                                    )
                                }
                                ForEach(message.copilotArtifacts) { artifact in
                                    AssignmentCopilotFactCardView(card: artifact)
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
                Text(ProductBrand.fullName)
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
        if codex.account != .signedIn { return "Sign in via Momentum ▸ Settings" }
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
