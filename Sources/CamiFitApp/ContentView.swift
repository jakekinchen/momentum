import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppExerciseSessionViewModel
    @ObservedObject var codex: CodexAppServerClient
    @StateObject private var liveSession = LiveSession()
    @StateObject private var chat = ChatViewModel()
    @StateObject private var memoryStore = KGMemoryStore()
    @State private var inspectorState = AppInspectorState()

    var body: some View {
        NavigationSplitView {
            SessionSidebar()
                .navigationSplitViewColumnWidth(min: 248, ideal: 286, max: 320)
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
        .navigationTitle("CamiFit")
        .navigationSubtitle(viewModel.state.selectedExerciseName ?? "No exercise")
        .environmentObject(viewModel)
        .environmentObject(liveSession)
        .environmentObject(chat)
        .environmentObject(codex)
        .onAppear {
            viewModel.loadAvailablePresets()
            viewModel.loadRecordedRuns()
            liveSession.refreshCameras()
            chat.codex = codex
            chat.memoryStore = memoryStore
            codex.start()
            memoryStore.load()
        }
        .onDisappear {
            liveSession.stop()
            codex.stop()
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
    @ObservedObject var liveSession: LiveSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            PoseStage(liveSession: liveSession)

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

            if let routine = model.activeRoutine {
                VStack {
                    HStack(spacing: 8) {
                        Text(routine.name).font(.caption.weight(.semibold))
                        Text("Block \(model.activeRoutineBlockIndex + 1) of \(routine.blocks.count)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("Next") { model.advanceRoutine() }.buttonStyle(.bordered).controlSize(.mini)
                    }
                    .padding(8)
                    .glassEffect(.regular, in: .capsule)
                    Spacer()
                }
                .padding(.top, 64)
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
                ActionControlBar(liveSession: liveSession)
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
    }
}

private struct PoseStage: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @ObservedObject var liveSession: LiveSession

    var body: some View {
        ZStack {
            if liveSession.running && liveSession.isLiveCamera {
                CameraPreview(session: liveSession.camera.session)
                    .background(Color.black)
                LivePoseOverlay(state: model.latestPoseOverlayState, sourceSize: liveSession.sourceSize)
                    .allowsHitTesting(false)
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
            Text("Press Live Camera for webcam tracking, or Demo to play a sample squat.")
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

private struct ActionControlBar: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @ObservedObject var liveSession: LiveSession

    private var liveActive: Bool { liveSession.running && liveSession.isLiveCamera }
    private var demoActive: Bool { liveSession.running && !liveSession.isLiveCamera }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if liveActive {
                        liveSession.stop()
                    } else {
                        liveSession.stop()
                        liveSession.start(viewModel: model)
                    }
                } label: {
                    Label(liveActive ? "Stop" : "Live Camera",
                          systemImage: liveActive ? "stop.fill" : "video.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(liveActive ? .red : .accentColor)
                .help(liveActive ? "Stop the live camera" : "Track reps from your webcam, in this window")

                Button {
                    if demoActive {
                        liveSession.stop()
                    } else {
                        liveSession.stop()
                        if let url = Self.demoFramesURL {
                            liveSession.startSynthetic(viewModel: model, framesURL: url)
                        }
                    }
                } label: {
                    Label(demoActive ? "Stop Demo" : "Demo",
                          systemImage: demoActive ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.glass)
                .help("Play the bundled synthetic squat trace in the viewer")

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

                Button {
                    model.resetLiveSession()
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

    private static var demoFramesURL: URL? {
        Bundle.module.url(forResource: "synthetic_squat_demo", withExtension: "jsonl", subdirectory: "Demo")
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

private struct SessionSidebar: View {
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
        .navigationTitle("Session")
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
                Text("CamiFit signs in with your ChatGPT account through Codex. The coach uses this account for every reply.")
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
                            colors: [.mint.opacity(0.92), .teal.opacity(0.82), .blue.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .mint.opacity(0.22), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("CamiFit Coach")
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
        if codex.account != .signedIn { return "Sign in via CamiFit ▸ Settings" }
        switch codex.state {
        case .idle: return "Idle"
        case .starting: return "Connecting to Codex…"
        case .ready: return "Powered by Codex"
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
        ("How's my squat form?", "figure.strengthtraining.functional"),
        ("How many reps should I do?", "repeat"),
        ("Give me a quick warm-up", "flame")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask your coach")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Questions about form, reps, and your session will live here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                            Spacer()
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
        Text(message.text)
            .font(.system(size: 13.5, weight: .regular, design: .rounded))
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
                .fill(.mint.opacity(0.16))
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
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
