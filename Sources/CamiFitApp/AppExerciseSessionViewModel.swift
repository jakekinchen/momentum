import CamiFitEngine
import Foundation

public struct AppPresetSummary: Equatable, Identifiable {
    public enum ExerciseKind: String, Equatable {
        case reps
        case hold
    }

    public enum TrackingReadiness: String, Equatable {
        case guideReady = "guide_ready"
        case referenceCaptureRequired = "reference_capture_required"

        public var displayText: String {
            switch self {
            case .guideReady:
                return "Guide ready"
            case .referenceCaptureRequired:
                return "Needs reference clip"
            }
        }
    }

    public let id: String
    public let name: String
    public let kind: ExerciseKind
    public let trackingReadiness: TrackingReadiness
    public let url: URL
}

public struct AppExerciseSessionState: Equatable {
    public var selectedExerciseID: String?
    public var selectedExerciseName: String?
    public var repCount: Int = 0
    public var holdSeconds: Double = 0
    public var holdTargetReached: Bool = false
    public var cueText: String?
    public var scoreText: String?
    public var diagnosticText: String?
    public var presetSourceDescription: String?

    public var holdProgressText: String {
        if holdTargetReached {
            return String(format: "%.1fs done", holdSeconds)
        }

        return String(format: "%.1fs", holdSeconds)
    }
}

public enum AppExerciseSessionError: Error, Equatable {
    case presetNotFound(String)
    case presetRequiresReferenceCapture(String)
    case routineBlockOutOfRange(Int)
    case invalidInlineExercise(String)
    case unguidedCatalogExercise(String)
}

public enum RoutineSessionPhase: Equatable {
    case idle
    case starting
    case guide(secondsRemaining: Int)
    case waitingForCamera
    case countdown(secondsRemaining: Int)
    case working
    case resting(secondsRemaining: Int)
    case paused
    case complete

    var canPause: Bool {
        switch self {
        case .guide, .waitingForCamera, .countdown, .working, .resting:
            return true
        case .idle, .starting, .paused, .complete:
            return false
        }
    }

    var ignoresLiveProgress: Bool {
        switch self {
        case .idle, .working:
            return false
        case .starting, .guide, .waitingForCamera, .countdown, .resting, .paused, .complete:
            return true
        }
    }
}

public struct RoutineSessionState: Equatable {
    public var phase: RoutineSessionPhase = .idle
}

public final class AppExerciseSessionViewModel: ObservableObject {
    @Published public private(set) var availablePresets: [AppPresetSummary] = []
    @Published public private(set) var availableRecordedRuns: [AppRecordedRunSummary] = []
    @Published public private(set) var selectedRecordedRunID: String?
    @Published public private(set) var state = AppExerciseSessionState()
    @Published public private(set) var lastPoseProviderRunSummary: AppPoseProviderRunSummary?
    @Published public private(set) var poseProviderRunStatus: AppPoseProviderRunStatus = .idle
    @Published public private(set) var mockWorkerPreflightStatus: AppMockWorkerPreflightStatus = .idle
    @Published public private(set) var latestHUDState: AppHUDState?
    @Published public private(set) var latestPoseOverlayState = AppPoseOverlayState.empty
    @Published public private(set) var lastFeedbackEvent: WorkoutFeedbackEvent?
    public private(set) var resolvedPresetSourceURL: URL?
    public private(set) var resolvedRecordedRunSourceURL: URL?

    private let presetSourceCandidates: [URL]
    private let recordedRunSourceCandidates: [URL]
    private var selectedProgram: ExerciseProgram?
    private var liveFrames: [PoseFrame] = []

    public var activeExerciseProgram: ExerciseProgram? {
        selectedProgram
    }

    public convenience init(presetsDirectory: URL) {
        self.init(
            presetSourceCandidates: [presetsDirectory],
            recordedRunSourceCandidates: AppRecordedRunCatalog.defaultSourceCandidates()
        )
    }

    public convenience init(recordedRunsDirectory: URL) {
        self.init(
            presetSourceCandidates: AppExerciseSessionViewModel.defaultPresetSourceCandidates(),
            recordedRunSourceCandidates: [recordedRunsDirectory]
        )
    }

    public convenience init() {
        self.init(
            presetSourceCandidates: AppExerciseSessionViewModel.defaultPresetSourceCandidates(),
            recordedRunSourceCandidates: AppRecordedRunCatalog.defaultSourceCandidates()
        )
    }

    public init(
        presetSourceCandidates: [URL],
        recordedRunSourceCandidates: [URL] = AppRecordedRunCatalog.defaultSourceCandidates()
    ) {
        self.presetSourceCandidates = presetSourceCandidates
        self.recordedRunSourceCandidates = recordedRunSourceCandidates
    }

    public func saveGeneratedExercise(_ program: ExerciseProgram, store: RegimenStore = RegimenStore()) throws {
        try store.saveExercise(program)
        loadAvailablePresets()
    }

    @Published public private(set) var activeRoutine: WorkoutRoutine?
    @Published public private(set) var activeRoutineBlockIndex: Int = 0
    @Published public private(set) var routineSession = RoutineSessionState()
    private var phaseBeforePause: RoutineSessionPhase?

    public var activeRoutineBlock: RoutineBlock? {
        guard let activeRoutine, activeRoutine.blocks.indices.contains(activeRoutineBlockIndex) else {
            return nil
        }
        return activeRoutine.blocks[activeRoutineBlockIndex]
    }

    public var activeRoutineProgressText: String? {
        guard let block = activeRoutineBlock else { return nil }
        if let reps = block.reps {
            let target = max(1, block.sets) * reps
            return "\(min(state.repCount, target))/\(target) reps"
        }
        if let holdSeconds = block.holdSeconds {
            let target = Double(max(1, block.sets)) * holdSeconds
            return "\(Int(min(state.holdSeconds, target)))/\(Int(target)) sec"
        }
        return nil
    }

    public func startRoutine(_ routine: WorkoutRoutine, atBlock index: Int = 0) throws {
        guard routine.blocks.indices.contains(index) else {
            throw AppExerciseSessionError.routineBlockOutOfRange(index)
        }
        for block in routine.blocks {
            try validateBlockExercise(block.exerciseRef)
        }
        activeRoutine = routine
        try activateRoutineBlock(at: index, phase: .starting)
    }

    public func advanceRoutine() {
        guard let routine = activeRoutine else { return }
        let next = activeRoutineBlockIndex + 1
        guard next < routine.blocks.count else {
            finishRoutine()
            return
        }
        try? activateRoutineBlock(at: next, phase: .starting)
    }

    public func activateRoutineBlock(at index: Int, phase: RoutineSessionPhase = .starting) throws {
        guard let routine = activeRoutine, routine.blocks.indices.contains(index) else {
            throw AppExerciseSessionError.routineBlockOutOfRange(index)
        }
        try activateBlockExercise(routine.blocks[index].exerciseRef)
        activeRoutineBlockIndex = index
        resetLiveSession()
        phaseBeforePause = nil
        routineSession.phase = phase
    }

    public func beginRoutineGuide(seconds: Int = 6) {
        guard activeRoutine != nil else { return }
        routineSession.phase = .guide(secondsRemaining: max(0, seconds))
    }

    public func tickRoutineGuide() {
        guard case let .guide(secondsRemaining) = routineSession.phase else { return }
        guard secondsRemaining > 1 else {
            routineSession.phase = .waitingForCamera
            return
        }
        routineSession.phase = .guide(secondsRemaining: secondsRemaining - 1)
    }

    public func beginRoutineCountdown(seconds: Int = 3) {
        guard activeRoutine != nil else { return }
        routineSession.phase = .countdown(secondsRemaining: max(0, seconds))
    }

    public func tickRoutineCountdown() {
        guard case let .countdown(secondsRemaining) = routineSession.phase else { return }
        guard secondsRemaining > 1 else {
            resetLiveSession()
            routineSession.phase = .working
            return
        }
        routineSession.phase = .countdown(secondsRemaining: secondsRemaining - 1)
    }

    public func pauseRoutine() {
        guard routineSession.phase.canPause else { return }
        phaseBeforePause = routineSession.phase
        routineSession.phase = .paused
    }

    public func resumeRoutine() {
        guard case .paused = routineSession.phase else { return }
        routineSession.phase = phaseBeforePause ?? .working
        phaseBeforePause = nil
    }

    public func toggleRoutinePause() {
        if case .paused = routineSession.phase {
            resumeRoutine()
        } else {
            pauseRoutine()
        }
    }

    public func cancelRoutine() {
        activeRoutine = nil
        activeRoutineBlockIndex = 0
        phaseBeforePause = nil
        routineSession.phase = .idle
    }

    public func completeActiveRoutineBlock() {
        guard let routine = activeRoutine,
              let block = activeRoutineBlock else { return }
        resetLiveSession()
        let hasNext = activeRoutineBlockIndex + 1 < routine.blocks.count
        let restSeconds = max(0, block.restSeconds ?? 0)
        if hasNext, restSeconds > 0 {
            routineSession.phase = .resting(secondsRemaining: restSeconds)
        } else {
            advanceRoutine()
        }
    }

    public func tickRoutineRest() {
        guard case let .resting(secondsRemaining) = routineSession.phase else { return }
        guard secondsRemaining > 1 else {
            advanceRoutine()
            return
        }
        routineSession.phase = .resting(secondsRemaining: secondsRemaining - 1)
    }

    /// Checks a routine block before mutating active routine state.
    private func validateBlockExercise(_ ref: ExerciseRef) throws {
        switch ref {
        case let .preset(id):
            try ensureGuideReadyPreset(id: id)
            _ = try programForPreset(id: id)
        case let .inline(program):
            if let error = RegimenBlockParser.validate(program: program) {
                throw AppExerciseSessionError.invalidInlineExercise(String(describing: error))
            }
            throw AppExerciseSessionError.invalidInlineExercise(
                "Inline exercises require accepted motion-reference promotion before guided execution."
            )
        case let .catalog(_, name):
            throw AppExerciseSessionError.unguidedCatalogExercise(name)
        }
    }

    /// Selects a routine block's exercise. Inline programs are drafts only until
    /// promoted through the source-preserving motion-reference gate.
    private func activateBlockExercise(_ ref: ExerciseRef, store: RegimenStore = RegimenStore()) throws {
        switch ref {
        case let .preset(id):
            try ensureGuideReadyPreset(id: id)
            try selectPreset(id: id)
        case let .inline(program):
            if let error = RegimenBlockParser.validate(program: program) {
                throw AppExerciseSessionError.invalidInlineExercise(String(describing: error))
            }
            throw AppExerciseSessionError.invalidInlineExercise(
                "Inline exercises require accepted motion-reference promotion before guided execution."
            )
        case let .catalog(_, name):
            throw AppExerciseSessionError.unguidedCatalogExercise(name)
        }
    }

    public func loadAvailablePresets() {
        let resolved = Self.resolvePresetSummaries(from: presetSourceCandidates)
        availablePresets = resolved.presets
        resolvedPresetSourceURL = resolved.sourceURL
        state.presetSourceDescription = resolved.sourceURL?.path
        if availablePresets.isEmpty {
            state.diagnosticText = "No presets found"
        }

        if state.selectedExerciseID == nil,
           let first = availablePresets.first(where: { $0.trackingReadiness == .guideReady }) ?? availablePresets.first {
            try? selectPreset(id: first.id)
        }
    }

    public func selectPreset(id: String) throws {
        guard let preset = availablePresets.first(where: { $0.id == id }) else {
            if AppExerciseTrackingGate.requiresReferenceCapture(id) {
                throw AppExerciseSessionError.presetRequiresReferenceCapture(id)
            }
            throw AppExerciseSessionError.presetNotFound(id)
        }
        guard preset.trackingReadiness == .guideReady else {
            throw AppExerciseSessionError.presetRequiresReferenceCapture(id)
        }

        let program = try ProgramLoader.load(from: preset.url)
        try activateProgram(program)
    }

    public func trackingReadiness(forPresetID id: String) -> AppPresetSummary.TrackingReadiness? {
        if availablePresets.isEmpty {
            loadAvailablePresets()
        }
        if let readiness = availablePresets.first(where: { $0.id == id })?.trackingReadiness {
            return readiness
        }
        if AppExerciseTrackingGate.requiresReferenceCapture(id) {
            return .referenceCaptureRequired
        }
        return nil
    }

    public func ensureGuideReadyPreset(id: String) throws {
        guard let readiness = trackingReadiness(forPresetID: id) else {
            throw AppExerciseSessionError.presetNotFound(id)
        }
        guard readiness == .guideReady else {
            throw AppExerciseSessionError.presetRequiresReferenceCapture(id)
        }
    }

    public func programForPreset(id: String) throws -> ExerciseProgram {
        if availablePresets.isEmpty {
            loadAvailablePresets()
        }
        guard let preset = availablePresets.first(where: { $0.id == id }) else {
            if AppExerciseTrackingGate.requiresReferenceCapture(id) {
                throw AppExerciseSessionError.presetRequiresReferenceCapture(id)
            }
            throw AppExerciseSessionError.presetNotFound(id)
        }
        guard preset.trackingReadiness == .guideReady else {
            throw AppExerciseSessionError.presetRequiresReferenceCapture(id)
        }
        return try ProgramLoader.load(from: preset.url)
    }

    public func activateProgram(_ program: ExerciseProgram) throws {
        guard Self.isApprovedGuideReadyProgram(program) else {
            throw AppExerciseSessionError.presetRequiresReferenceCapture(program.id)
        }
        activateTrustedGuideProgram(program)
    }

    func activateTrustedGuideProgram(_ program: ExerciseProgram) {
        selectedProgram = program
        state = AppExerciseSessionState(
            selectedExerciseID: program.id,
            selectedExerciseName: program.name,
            presetSourceDescription: resolvedPresetSourceURL?.path
        )
    }

    public func loadRecordedRuns() {
        let resolved = AppRecordedRunCatalog.resolveRecordedRuns(from: recordedRunSourceCandidates)
        availableRecordedRuns = resolved.runs
        resolvedRecordedRunSourceURL = resolved.sourceURL

        if availableRecordedRuns.isEmpty {
            state.diagnosticText = "No recorded runs found"
            selectedRecordedRunID = nil
            return
        }

        if selectedRecordedRunID == nil {
            selectedRecordedRunID = availableRecordedRuns.first?.id
        }
    }

    @discardableResult
    public func runRecordedRun(id: String) -> AppPoseProviderRunSummary {
        loadRecordedRuns()

        guard let run = availableRecordedRuns.first(where: { $0.id == id }) else {
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "Recorded run not found: \(id)",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(
                from: summary,
                descriptor: AppPoseProviderRunDescriptor(mode: "recorded-run", source: "recorded:\(id)")
            )
            return summary
        }

        selectedRecordedRunID = run.id
        let provider = MediaPipePoseProvider(jsonlURL: run.url)
        return runRecordedProvider(
            provider,
            selectedPresetID: run.presetID,
            statusDescriptor: AppPoseProviderRunDescriptor(mode: "recorded-run", source: "recorded:\(run.id)")
        )
    }

    @discardableResult
    public func runRecordedProvider(
        _ provider: PoseProvider,
        selectedPresetID requestedPresetID: String? = nil
    ) -> AppPoseProviderRunSummary {
        runRecordedProvider(
            provider,
            selectedPresetID: requestedPresetID,
            statusDescriptor: AppPoseProviderRunDescriptor(mode: "provider", source: "direct-provider")
        )
    }

    @discardableResult
    private func runRecordedProvider(
        _ provider: PoseProvider,
        selectedPresetID requestedPresetID: String?,
        statusDescriptor: AppPoseProviderRunDescriptor
    ) -> AppPoseProviderRunSummary {
        poseProviderRunStatus = .running(statusDescriptor)
        loadAvailablePresets()

        guard let presetID = requestedPresetID ?? state.selectedExerciseID ?? availablePresets.first?.id else {
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "No preset selected",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(from: summary, descriptor: statusDescriptor)
            return summary
        }

        let session = AppPoseProviderSession(provider: provider, viewModel: self)
        let summary = session.run(selectedPresetID: presetID)
        lastPoseProviderRunSummary = summary
        updateDisplayState(from: summary)
        updateRunStatus(from: summary, descriptor: statusDescriptor)
        return summary
    }

    @discardableResult
    public func runConfiguredPoseProvider(
        mode: AppPoseProviderMode,
        factory: AppPoseProviderFactory? = nil
    ) -> AppPoseProviderRunSummary {
        let providerFactory = factory ?? AppPoseProviderFactory(recordedRunSourceCandidates: recordedRunSourceCandidates)

        do {
            let configured = try providerFactory.configuredProvider(for: mode)
            let descriptor = Self.runDescriptor(for: configured)
            poseProviderRunStatus = .running(descriptor)
            if let recordedRunID = configured.recordedRunID {
                selectedRecordedRunID = recordedRunID
                resolvedRecordedRunSourceURL = configured.recordedRunSourceURL
            }
            return runRecordedProvider(
                configured.provider,
                selectedPresetID: configured.selectedPresetID,
                statusDescriptor: descriptor
            )
        } catch {
            let descriptor = Self.runDescriptor(for: mode)
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "Pose provider configuration failed: \(error)",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(from: summary, descriptor: descriptor)
            return summary
        }
    }

    @discardableResult
    public func runMockWorkerProvider(
        workerScriptURL: URL = AppExerciseSessionViewModel.defaultMockWorkerScriptURL(),
        selectedPresetID: String = "bodyweight_squat",
        fixture: String = "squat_bottom",
        frameID: Int = 1,
        timestampMS: Int64 = 1_000
    ) -> AppPoseProviderRunSummary {
        let configuration = AppMockWorkerPoseProviderConfiguration(
            workerScriptURL: workerScriptURL,
            selectedPresetID: selectedPresetID,
            fixture: fixture,
            frameID: frameID,
            timestampMS: timestampMS
        )

        return runConfiguredPoseProvider(mode: .mockWorker(configuration))
    }

    @discardableResult
    public func preflightMockWorker(
        workerScriptURL: URL = AppExerciseSessionViewModel.defaultMockWorkerScriptURL()
    ) -> AppMockWorkerPreflightStatus {
        mockWorkerPreflightStatus = .checking(workerScriptURL)

        guard FileManager.default.fileExists(atPath: workerScriptURL.path) else {
            let status = AppMockWorkerPreflightStatus.failed(
                AppMockWorkerPreflightFailure(
                    workerScriptURL: workerScriptURL,
                    diagnosticText: "mock worker script not found: \(workerScriptURL.path)"
                )
            )
            mockWorkerPreflightStatus = status
            return status
        }

        let provider = PoseWorkerSubprocessProvider(workerScriptURL: workerScriptURL)
        do {
            let health = try provider.health()
            let status = AppMockWorkerPreflightStatus.succeeded(
                AppMockWorkerPreflightSuccess(
                    workerScriptURL: workerScriptURL,
                    command: provider.launchCommandDescription,
                    runningMode: health.runningMode,
                    message: health.message
                )
            )
            mockWorkerPreflightStatus = status
            return status
        } catch {
            let status = AppMockWorkerPreflightStatus.failed(
                AppMockWorkerPreflightFailure(
                    workerScriptURL: workerScriptURL,
                    diagnosticText: "mock worker preflight failed: \(error)"
                )
            )
            mockWorkerPreflightStatus = status
            return status
        }
    }

    @discardableResult
    public func process(frames: [PoseFrame]) throws -> AppExerciseSessionState {
        guard let selectedProgram else {
            loadAvailablePresets()
            guard self.selectedProgram != nil else {
                return state
            }

            return try process(frames: frames)
        }

        var recorder = try EngineTraceRecorder(program: selectedProgram)
        let trace = recorder.record(frames: frames)
        guard let last = trace.last else {
            return state
        }

        state.repCount = last.rep.repCount

        if let hold = last.hold {
            state.holdSeconds = hold.heldSeconds
            state.holdTargetReached = hold.targetReached
        } else {
            state.holdSeconds = 0
            state.holdTargetReached = false
        }

        state.cueText = last.formSummary.selectedCue
        state.scoreText = last.formSummary.score.map { String(format: "%.3f", $0) }
        state.diagnosticText = diagnosticText(from: last)
        updateRoutineProgressIfNeeded()
        return state
    }

    /// Feed one live camera frame: accumulate, re-run the engine over the buffer, and publish
    /// updated reps/form + the skeleton overlay. Swallows engine errors so a single bad frame
    /// never breaks the live loop.
    public func ingestLiveFrame(_ frame: PoseFrame) {
        updateLiveOverlay(with: frame)
        guard activeRoutine == nil || !routineSession.phase.ignoresLiveProgress else {
            return
        }

        let previousRepCount = state.repCount
        let wasHoldTargetReached = state.holdTargetReached
        liveFrames.append(frame)
        do {
            _ = try process(frames: liveFrames)
            publishStandaloneFeedbackIfNeeded(
                previousRepCount: previousRepCount,
                wasHoldTargetReached: wasHoldTargetReached
            )
        } catch {
            state.diagnosticText = "live engine error: \(error)"
        }
    }

    public func updateLiveOverlay(with frame: PoseFrame) {
        latestPoseOverlayState = AppPoseOverlayState(frame: frame)
    }

    public func applyExerciseFrameResult(_ result: ExerciseFrameResult, program: ExerciseProgram) throws {
        guard Self.isApprovedGuideReadyProgram(program) else {
            throw AppExerciseSessionError.presetRequiresReferenceCapture(program.id)
        }
        applyTrustedExerciseFrameResult(result, program: program)
    }

    func applyTrustedExerciseFrameResult(_ result: ExerciseFrameResult, program: ExerciseProgram) {
        selectedProgram = program
        state.selectedExerciseID = program.id
        state.selectedExerciseName = program.name

        switch result.target {
        case .reps:
            state.repCount = result.repsCompleted
            state.holdSeconds = 0
            state.holdTargetReached = false
        case .holdSeconds:
            state.repCount = 0
            state.holdSeconds = result.holdSeconds
            state.holdTargetReached = result.isComplete
        }

        state.cueText = result.cueText
        state.scoreText = result.scoreText
        state.diagnosticText = result.diagnosticText
    }

    func publishFeedbackEvent(_ event: WorkoutFeedbackEvent) {
        lastFeedbackEvent = event
    }

    public func resetLiveSession() {
        liveFrames.removeAll()
        state.repCount = 0
        state.holdSeconds = 0
        state.holdTargetReached = false
        state.cueText = nil
        state.diagnosticText = nil
        latestPoseOverlayState = AppPoseOverlayState.empty
    }

    private func publishStandaloneFeedbackIfNeeded(previousRepCount: Int, wasHoldTargetReached: Bool) {
        guard let selectedProgram,
              let target = SetTarget.defaultTarget(for: selectedProgram) else {
            return
        }

        switch target {
        case let .reps(targetReps):
            guard state.repCount > previousRepCount else { return }
            publishFeedbackEvent(.repCounted(
                repsCompleted: state.repCount,
                targetReps: targetReps,
                cueText: state.cueText,
                isSetComplete: state.repCount >= targetReps
            ))
        case .holdSeconds:
            guard !wasHoldTargetReached, state.holdTargetReached else { return }
            publishFeedbackEvent(.holdComplete(heldSeconds: state.holdSeconds))
        }
    }

    private func finishRoutine() {
        activeRoutine = nil
        activeRoutineBlockIndex = 0
        phaseBeforePause = nil
        routineSession.phase = .complete
    }

    private func updateRoutineProgressIfNeeded() {
        guard activeRoutine != nil,
              routineSession.phase == .working,
              let block = activeRoutineBlock,
              routineBlockTargetReached(block) else {
            return
        }
        completeActiveRoutineBlock()
    }

    private func routineBlockTargetReached(_ block: RoutineBlock) -> Bool {
        if let reps = block.reps {
            return state.repCount >= max(1, block.sets) * reps
        }
        if let holdSeconds = block.holdSeconds {
            return state.holdSeconds >= Double(max(1, block.sets)) * holdSeconds || state.holdTargetReached
        }
        return false
    }

    static func defaultPresetSourceCandidates(
        bundleURL: URL = Bundle.main.bundleURL,
        currentDirectory: URL? = nil
    ) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = AppResourceBundle.directory(named: "Presets") {
            candidates.append(resourceURL)
        }

        if bundleURL.pathExtension != "app" {
            let directory = currentDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            candidates.append(directory.appendingPathComponent("Presets"))
        }

        candidates.append(RegimenStore.userPresetsDirectory())
        return candidates
    }

    public static func defaultMockWorkerScriptURL(
        currentDirectory: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        resourceURL: URL? = Bundle.main.resourceURL
    ) -> URL {
        if bundleURL.pathExtension == "app" {
            let resources = resourceURL ?? bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            return resources.appendingPathComponent("pose_worker/pose_worker.py")
        }

        let directory = currentDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return directory.appendingPathComponent("pose_worker/pose_worker.py")
    }

    private static func runDescriptor(for configured: AppConfiguredPoseProvider) -> AppPoseProviderRunDescriptor {
        AppPoseProviderRunDescriptor(
            mode: runModeDescription(for: configured.mode),
            source: configured.sourceDescription
        )
    }

    private static func runDescriptor(for mode: AppPoseProviderMode) -> AppPoseProviderRunDescriptor {
        AppPoseProviderRunDescriptor(
            mode: runModeDescription(for: mode),
            source: runSourceDescription(for: mode)
        )
    }

    private static func runModeDescription(for mode: AppPoseProviderMode) -> String {
        switch mode {
        case .recordedRun:
            return "recorded-run"
        case .mockWorker:
            return "mock-worker"
        }
    }

    private static func runSourceDescription(for mode: AppPoseProviderMode) -> String {
        switch mode {
        case let .recordedRun(id):
            return "recorded:\(id)"
        case let .mockWorker(configuration):
            return "mock-worker:\(configuration.workerScriptURL.path)"
        }
    }

    private static func resolvePresetSummaries(from candidates: [URL]) -> (sourceURL: URL?, presets: [AppPresetSummary]) {
        let merged = mergedPresetSummaries(from: candidates)
        let source = candidates.first { !loadPresetSummaries(from: $0).isEmpty }
        return (source, merged)
    }

    /// Merge every candidate directory; first candidate wins on id collision so
    /// mutable user presets cannot shadow bundled guide-ready definitions.
    static func mergedPresetSummaries(from candidates: [URL]) -> [AppPresetSummary] {
        var byID: [String: AppPresetSummary] = [:]
        for candidate in candidates {
            for preset in loadPresetSummaries(from: candidate) where byID[preset.id] == nil {
                byID[preset.id] = preset
            }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    private static func loadPresetSummaries(from directory: URL) -> [AppPresetSummary] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let program = try? ProgramLoader.load(from: url) else {
                    return nil
                }
                guard isApprovedGuideReadyPreset(program, at: url) else {
                    return nil
                }
                let kind: AppPresetSummary.ExerciseKind = program.hold == nil ? .reps : .hold
                return AppPresetSummary(
                    id: program.id,
                    name: program.name,
                    kind: kind,
                    trackingReadiness: .guideReady,
                    url: url
                )
            }
            .sorted { $0.name < $1.name }
    }

    private static func isApprovedGuideReadyPreset(_ program: ExerciseProgram, at url: URL) -> Bool {
        guard AppExerciseTrackingGate.guideReadyPresetIDs.contains(program.id),
              let approvedURL = AppResourceBundle.url(
                forResource: program.id,
                withExtension: "json",
                subdirectory: "Presets"
              ),
              let candidateData = try? Data(contentsOf: url),
              let approvedData = try? Data(contentsOf: approvedURL) else {
            return false
        }
        return candidateData == approvedData
    }

    private static func isApprovedGuideReadyProgram(_ program: ExerciseProgram) -> Bool {
        guard AppExerciseTrackingGate.guideReadyPresetIDs.contains(program.id),
              let approvedURL = AppResourceBundle.url(
                forResource: program.id,
                withExtension: "json",
                subdirectory: "Presets"
              ),
              let approvedProgram = try? ProgramLoader.load(from: approvedURL) else {
            return false
        }
        return approvedProgram == program
    }

    private func diagnosticText(from traceFrame: EngineTraceFrame) -> String? {
        if let invalidReason = traceFrame.rep.invalidReason {
            return invalidReason
        }

        if traceFrame.hold?.valid == false {
            return traceFrame.hold?.notAccumulatingReason
        }

        return nil
    }

    private func updateDisplayState(from summary: AppPoseProviderRunSummary) {
        latestHUDState = AppHUDState(summary: summary)

        guard summary.diagnosticText == nil, let latestPoseFrame = summary.latestPoseFrame else {
            latestPoseOverlayState = .empty
            return
        }

        latestPoseOverlayState = AppPoseOverlayState(frame: latestPoseFrame)
    }

    private func updateRunStatus(
        from summary: AppPoseProviderRunSummary,
        descriptor: AppPoseProviderRunDescriptor
    ) {
        if let diagnosticText = summary.diagnosticText {
            poseProviderRunStatus = .failed(
                AppPoseProviderRunStatusFailure(descriptor: descriptor, diagnosticText: diagnosticText)
            )
        } else {
            poseProviderRunStatus = .succeeded(
                AppPoseProviderRunStatusSummary(descriptor: descriptor, frameCount: summary.frameCount)
            )
        }
    }
}
