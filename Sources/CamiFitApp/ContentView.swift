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

struct ContentView: View {
    @EnvironmentObject private var onboarding: OnboardingCoordinator
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    @ObservedObject var codex: CodexAppServerClient
    @AppStorage("camifit.onboarding.completed") private var didCompleteOnboarding = false
    @StateObject private var routineRunner: RoutineRunner
    @StateObject private var liveSession = LiveSession()
    @StateObject private var chat = ChatViewModel()
    @StateObject private var memoryStore = KGMemoryStore()
    @StateObject private var routineLibrary = RoutineLibraryStore()
    @State private var inspectorState = AppInspectorState()

    init(viewModel: AppExerciseSessionViewModel, codex: CodexAppServerClient) {
        self.viewModel = viewModel
        self.codex = codex
        _routineRunner = StateObject(wrappedValue: RoutineRunner(viewModel: viewModel))
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebar()
                .navigationSplitViewColumnWidth(min: 280, ideal: 390, max: 480)
        } detail: {
            DetailScene()
                .toolbar {
                    ToolbarSpacer(.flexible)

                    ToolbarItemGroup {
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            viewModel.resetLiveSession()
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                        .help("Reset session")

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
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
                }
        }
        .navigationTitle("Momentum")
        .navigationSubtitle("A Future product")
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
        .onAppear {
            viewModel.loadAvailablePresets()
            if let guideExerciseID = CamiFitLaunchEnvironment.guideExerciseID {
                try? viewModel.selectPreset(id: guideExerciseID)
                didCompleteOnboarding = true
                onboarding.dismiss()
            }
            viewModel.loadRecordedRuns()
            routineLibrary.load()
            liveSession.refreshCameras()
            chat.codex = codex
            chat.memoryStore = memoryStore
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
    @EnvironmentObject private var liveSession: LiveSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeroPreviewCard(liveSession: liveSession)

                SessionStatusStrip()
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
    @ObservedObject var liveSession: LiveSession
    @State private var feedMode: HeroFeedMode = CamiFitLaunchEnvironment.startsInGuideMode ? .avatarGuide : .tracking
    @State private var showsSkeletonOverlay = true

    private var displayedFeedMode: HeroFeedMode {
        routineRunner.phase.usesGuide ? .avatarGuide : feedMode
    }

    private var overlayBlockName: String? {
        if case .rest = routineRunner.phase {
            return routineRunner.nextBlockTitle
        }
        return routineRunner.currentBlock?.title
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PoseStage(liveSession: liveSession, feedMode: displayedFeedMode, showsSkeletonOverlay: showsSkeletonOverlay)

            if displayedFeedMode != .avatarGuide {
                VStack(alignment: .leading) {
                    HStack(alignment: .top, spacing: 10) {
                        StatTile(label: "Reps", value: "\(model.state.repCount)", systemImage: "repeat")
                        StatTile(label: "Hold", value: model.state.holdProgressText, systemImage: "timer")
                        StatTile(label: "Score", value: model.state.scoreText ?? "n/a", systemImage: "rosette")
                        Spacer(minLength: 0)
                    }
                    Spacer()
                }
                .padding(14)
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
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
                        Label(displayedFeedMode == .avatarGuide ? "Camera" : "Guide",
                              systemImage: displayedFeedMode == .avatarGuide ? "video.fill" : "figure.strengthtraining.functional")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(displayedFeedMode == .avatarGuide ? .cyan : .secondary)
                    .help(displayedFeedMode == .avatarGuide ? "Return to camera tracking" : "Show the avatar guide for the selected exercise")
                }
                Spacer()
            }
            .padding(14)

            if let routine = routineRunner.currentRoutine {
                VStack {
                    HStack(spacing: 8) {
                        Text(routine.name).font(.caption.weight(.semibold))
                        if let step = routineRunner.routineStepText {
                            Text(step)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let set = routineRunner.setText {
                            Text(set)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let progress = routineRunner.progressText {
                            Text(progress)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(8)
                    .glassEffect(.regular, in: .capsule)
                    Spacer()
                }
                .padding(.top, 64)
            }

            RoutinePhaseOverlay(
                phase: routineRunner.phase,
                pipelineStatus: liveSession.poseReadiness.displayText,
                currentBlockName: overlayBlockName,
                progressText: routineRunner.progressText,
                onResume: { routineRunner.resume() },
                onEnd: {
                    routineRunner.cancel()
                    liveSession.stop()
                },
                onRestart: { routineRunner.restartCurrentSet() },
                onReplayGuide: { routineRunner.replayGuide() },
                onSkipGuide: { routineRunner.skipGuide() },
                onSkipRest: { routineRunner.skipRest() },
                onAddRest: { routineRunner.addRest(seconds: 15) }
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
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .onChange(of: routineRunner.phase) { _, phase in
            syncLivePipeline(for: phase)
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
}

private enum HeroFeedMode: Equatable {
    case tracking
    case avatarGuide
}

private struct PoseStage: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @ObservedObject var liveSession: LiveSession
    let feedMode: HeroFeedMode
    let showsSkeletonOverlay: Bool

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

                PoseOverlayView(state: model.latestPoseOverlayState)
                    .padding(18)

                if model.latestPoseOverlayState.points.isEmpty && !liveSession.running {
                    placeholderOverlay
                }
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

private struct RoutinePhaseOverlay: View {
    let phase: RoutineRunPhase
    let pipelineStatus: String
    let currentBlockName: String?
    let progressText: String?
    let onResume: () -> Void
    let onEnd: () -> Void
    let onRestart: () -> Void
    let onReplayGuide: () -> Void
    let onSkipGuide: () -> Void
    let onSkipRest: () -> Void
    let onAddRest: () -> Void

    var body: some View {
        switch phase {
        case .idle, .working:
            EmptyView()
        case .preparing:
            overlay(title: "Routine starting", detail: nil, symbol: "play.circle.fill")
        case let .guide(secondsRemaining):
            overlay(
                title: currentBlockName ?? "Watch the guide",
                detail: "\(secondsRemaining)s",
                symbol: "figure.strengthtraining.functional",
                actions: {
                    Button("Replay", action: onReplayGuide)
                    Button("Skip", action: onSkipGuide)
                }
            )
        case let .awaitingCamera(readiness):
            overlay(title: "Waiting for camera", detail: readiness.displayText, symbol: "video.fill")
        case let .awaitingPose(message):
            overlay(title: message ?? "Step into frame", detail: pipelineStatus, symbol: "figure.walk.motion")
        case let .countdown(secondsRemaining):
            overlay(title: "\(secondsRemaining)", detail: "Get ready", symbol: "timer")
        case let .rest(secondsRemaining):
            overlay(
                title: "Rest",
                detail: nextDetail(secondsRemaining: secondsRemaining),
                symbol: "timer",
                actions: {
                    Button("Skip Rest", action: onSkipRest)
                    Button("+15s", action: onAddRest)
                }
            )
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
                title: "Routine complete",
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

    private func nextDetail(secondsRemaining: Int) -> String {
        if let currentBlockName {
            return "\(secondsRemaining)s • Next: \(currentBlockName)"
        }
        return "\(secondsRemaining)s"
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
    private var routineOwnsCamera: Bool { routineRunner.phase.needsCamera }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if liveActive {
                        liveSession.stop()
                    } else {
                        liveSession.stop()
                        feedMode = .tracking
                        liveSession.start(viewModel: model)
                    }
                } label: {
                    Label(liveActive ? "Stop" : "Live Camera",
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

                Spacer(minLength: 12)

                if routineRunner.phase.isActive || routineRunner.isPaused {
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

    private var pauseTitle: String {
        routineRunner.isPaused ? "Resume" : "Pause"
    }

    private var pauseIcon: String {
        routineRunner.isPaused ? "play.fill" : "pause.fill"
    }
}

// MARK: - Status strip

private struct SessionStatusStrip: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Chip(systemImage: providerGlyph, text: model.poseProviderRunStatus.displayText, tint: providerTint)
                Chip(systemImage: mockGlyph, text: model.mockWorkerPreflightStatus.displayText, tint: mockTint)
                if let summary = model.lastPoseProviderRunSummary {
                    Chip(systemImage: "film", text: "\(summary.frameCount) frames", tint: .blue, foreground: .primary)
                }
                Chip(systemImage: "circle.grid.cross", text: "\(model.latestPoseOverlayState.points.count) points", tint: .cyan, foreground: .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 2)
    }

    private var providerGlyph: String {
        switch model.poseProviderRunStatus {
        case .idle: "pause.circle"
        case .running: "play.circle"
        case .succeeded: "checkmark.circle"
        case .failed: "xmark.octagon"
        }
    }

    private var providerTint: Color {
        switch model.poseProviderRunStatus {
        case .idle: .secondary
        case .running: .orange
        case .succeeded: .green
        case .failed: .red
        }
    }

    private var mockGlyph: String {
        switch model.mockWorkerPreflightStatus {
        case .idle: "questionmark.circle"
        case .checking: "hourglass"
        case .succeeded: "checkmark.seal"
        case .failed: "xmark.octagon"
        }
    }

    private var mockTint: Color {
        switch model.mockWorkerPreflightStatus {
        case .idle: .secondary
        case .checking: .orange
        case .succeeded: .green
        case .failed: .red
        }
    }
}

// MARK: - Sidebar (session inputs)

private enum SidebarTab: String, CaseIterable {
    case settings
    case routines

    var title: String {
        switch self {
        case .settings: "Settings"
        case .routines: "Routines"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .routines: "list.bullet.rectangle"
        }
    }
}

private struct SessionSidebar: View {
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

private struct SessionSettingsSidebar: View {
    var body: some View {
        Form {
            ExerciseSection()
            CameraSection()
            #if DEBUG
            DeveloperSection()
            #endif
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollContentBackground(.hidden)
    }
}

private struct RoutineLibrarySidebar: View {
    @EnvironmentObject private var routineLibrary: RoutineLibraryStore

    var body: some View {
        NavigationStack {
            List {
                if routineLibrary.routines.isEmpty {
                    Text("No saved routines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(routineLibrary.routines) { routine in
                        NavigationLink(value: routine.id) {
                            RoutineSidebarRow(routine: routine)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            routineLibrary.select(routine)
                        })
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: String.self) { routineID in
                if let routine = routineLibrary.routines.first(where: { $0.id == routineID }) {
                    RoutineDetailPanel(routine: routine)
                } else {
                    Text("Routine unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { routineLibrary.load() }
    }
}

private struct RoutineSidebarRow: View {
    let routine: WorkoutRoutine

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
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

    private var detailText: String {
        let blocks = routine.blocks.count
        let blockText = "\(blocks) \(blocks == 1 ? "block" : "blocks")"
        guard let description = routine.description, !description.isEmpty else {
            return blockText
        }
        return "\(blockText) · \(description)"
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

            VStack(spacing: 8) {
                ForEach(Array(routine.blocks.enumerated()), id: \.offset) { index, block in
                    RoutineDetailBlockRow(
                        index: index,
                        block: block,
                        exerciseName: exerciseName(for: block.exerciseRef),
                        status: status(for: block),
                        onPractice: { practice(index) },
                        onStartFromHere: { startFrom(index) }
                    )
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.title3.weight(.semibold))
                if let description = routine.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(routine.blocks.count) \(routine.blocks.count == 1 ? "exercise" : "exercises")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                startFrom(0)
            } label: {
                Label("Start Routine", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!isRunnable)
        }
    }

    private var isRunnable: Bool {
        (try? compiler().compile(routine)) != nil
    }

    private func status(for block: RoutineBlock) -> RoutineBlockRunStatus {
        let single = WorkoutRoutine(
            id: "\(routine.id)-block",
            name: routine.name,
            blocks: [block]
        )
        do {
            let compiled = try compiler().compile(single)
            let target = compiled.blocks.first?.targetText ?? "Ready"
            return .ready(target)
        } catch {
            return .unavailable(String(describing: error))
        }
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
    let block: RoutineBlock
    let exerciseName: String
    let status: RoutineBlockRunStatus
    let onPractice: () -> Void
    let onStartFromHere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(status.detail, systemImage: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(status.tint)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
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
                .disabled(!status.isReady)

                Button {
                    onStartFromHere()
                } label: {
                    Label("Start From Here", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!status.isReady)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var detailText: String {
        let target: String
        if let reps = block.reps {
            target = "\(block.sets)x\(reps) reps"
        } else if let holdSeconds = block.holdSeconds {
            target = "\(block.sets)x\(Int(holdSeconds))s hold"
        } else {
            target = "\(block.sets) sets"
        }

        guard let restSeconds = block.restSeconds, restSeconds > 0 else {
            return target
        }
        return "\(target) • \(restSeconds)s rest"
    }
}

private struct CameraSection: View {
    @EnvironmentObject private var liveSession: LiveSession

    var body: some View {
        Section("Camera") {
            Picker("Input", selection: $liveSession.selectedCameraID) {
                Text("Automatic").tag(String?.none)
                ForEach(liveSession.availableCameras) { camera in
                    Text(camera.name).tag(Optional(camera.id))
                }
            }
            .onChange(of: liveSession.selectedCameraID) { _, newID in
                liveSession.camera.setDevice(newID)
            }

            if liveSession.availableCameras.isEmpty {
                Text("No cameras detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                liveSession.refreshCameras()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
        }
    }
}

private struct ExerciseSection: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel

    var body: some View {
        Section("Exercise") {
            Picker("Exercise", selection: selectedExerciseBinding) {
                ForEach(model.availablePresets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }

            if let kind = selectedKind {
                Label(kind == .reps ? "Counts reps" : "Timed hold",
                      systemImage: kind == .reps ? "repeat" : "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedKind: AppPresetSummary.ExerciseKind? {
        model.availablePresets.first { $0.id == model.state.selectedExerciseID }?.kind
    }

    private var selectedExerciseBinding: Binding<String?> {
        Binding {
            model.state.selectedExerciseID
        } set: { selectedID in
            guard let selectedID else { return }
            try? model.selectPreset(id: selectedID)
        }
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
        Section("Developer") {
            Picker("Recorded run", selection: selectedRecordedRunBinding) {
                ForEach(model.availableRecordedRuns) { run in
                    Text(run.displayName).tag(Optional(run.id))
                }
            }

            Button {
                guard let id = model.selectedRecordedRunID else { return }
                _ = model.runRecordedRun(id: id)
            } label: {
                Label("Run recorded sample", systemImage: "play.rectangle")
            }
            .buttonStyle(.glass)
            .disabled(model.selectedRecordedRunID == nil)

            Button {
                model.runMockWorkerProvider()
            } label: {
                Label("Run mock worker", systemImage: "cpu")
            }
            .buttonStyle(.glass)

            Button {
                model.preflightMockWorker()
            } label: {
                Label("Check mock worker", systemImage: "stethoscope")
            }
            .buttonStyle(.glass)
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
    let id = UUID()
    let role: Role
    var text: String
    var regimen: [RegimenResult] = []
    var memoryArtifacts: [KGMemoryChatArtifact] = []
}

/// UI-shell chat model: the transcript and composer are real; the responder is a
/// placeholder until a coaching brain (local or Claude) is wired in.
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published private(set) var isResponding = false

    weak var codex: CodexAppServerClient?
    weak var memoryStore: KGMemoryStore?

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

    private func append(_ text: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += text
    }

    private func finish(_ id: UUID, sourceUserText: String) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[idx].text.isEmpty { messages[idx].text = "(No response.)" }
        let rawAssistantText = messages[idx].text
        messages[idx].regimen = RegimenBlockParser.parse(message: rawAssistantText)
        messages[idx].memoryArtifacts = KGMemoryChatBridge.applyProposals(
            in: rawAssistantText,
            sourceUserText: sourceUserText,
            store: memoryStore
        )
        messages[idx].text = KGMemoryProposalParser.displayText(removingProposalBlocks: rawAssistantText)
    }

    private func setError(_ message: String, on id: UUID) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let prefix = messages[idx].text.isEmpty ? "" : "\n\n"
        messages[idx].text += "\(prefix)⚠️ \(message)"
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
                                ChatBubble(message: message)
                                ForEach(Array(message.regimen.enumerated()), id: \.offset) { _, result in
                                    RegimenCard(result: result)
                                }
                                ForEach(message.memoryArtifacts) { artifact in
                                    ChatMemoryArtifactCard(artifact: artifact)
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

private struct ChatHeader: View {
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

private struct StatTile: View {
    var label: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(.cyan)
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 76, alignment: .leading)
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
