import CamiFitEngine
import Combine
import Foundation

public enum CameraReadiness: Equatable {
    case idle
    case requestingPermission
    case denied
    case noDevice
    case starting
    case streaming(CGSize)
    case failed(String)

    public var displayText: String {
        switch self {
        case .idle:
            return "Camera idle"
        case .requestingPermission:
            return "Requesting camera permission"
        case .denied:
            return "Camera permission denied"
        case .noDevice:
            return "No camera found"
        case .starting:
            return "Camera starting"
        case let .streaming(size):
            guard size != .zero else { return "Camera running" }
            return "Camera running \(Int(size.width))x\(Int(size.height))"
        case let .failed(message):
            return message
        }
    }

    public var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }
}

public enum PosePipelineReadiness: Equatable {
    case idle
    case workerStarting
    case camera(CameraReadiness)
    case waitingForFirstPose
    case ready
    case degraded(String)
    case failed(String)

    public var displayText: String {
        switch self {
        case .idle:
            return "Pose pipeline idle"
        case .workerStarting:
            return "Starting pose worker"
        case let .camera(readiness):
            return readiness.displayText
        case .waitingForFirstPose:
            return "Step into frame"
        case .ready:
            return "Pose ready"
        case let .degraded(message):
            return message
        case let .failed(message):
            return message
        }
    }
}

public struct RoutineCompletionSummary: Equatable {
    public let scope: WorkoutCompletionScope
    public let routineName: String
    public let completedSets: Int
    public let completedBlocks: Int
    public let completedExerciseNames: [String]
    public let durationSeconds: Int
    public let finalProgressText: String
    public let formSignals: [String]
    public let cameraIssues: [String]

    public init(
        scope: WorkoutCompletionScope = .routine,
        routineName: String,
        completedSets: Int,
        completedBlocks: Int,
        completedExerciseNames: [String] = [],
        durationSeconds: Int = 0,
        finalProgressText: String? = nil,
        formSignals: [String] = [],
        cameraIssues: [String] = []
    ) {
        self.scope = scope
        self.routineName = routineName
        self.completedSets = completedSets
        self.completedBlocks = completedBlocks
        self.completedExerciseNames = completedExerciseNames
        self.durationSeconds = durationSeconds
        self.finalProgressText = finalProgressText ?? "\(completedSets) \(completedSets == 1 ? "set" : "sets") complete"
        self.formSignals = formSignals
        self.cameraIssues = cameraIssues
    }

    public var displayText: String {
        finalProgressText
    }
}

public enum RoutineRunResumePhase: Equatable {
    case preparing
    case guide(secondsRemaining: Int)
    case awaitingCamera(CameraReadiness)
    case awaitingPose(String?)
    case countdown(secondsRemaining: Int)
    case working
    case rest(secondsRemaining: Int)
}

public enum RoutineRunPhase: Equatable {
    case idle
    case preparing
    case guide(secondsRemaining: Int)
    case awaitingCamera(CameraReadiness)
    case awaitingPose(String?)
    case countdown(secondsRemaining: Int)
    case working
    case rest(secondsRemaining: Int)
    case paused(previous: RoutineRunResumePhase)
    case complete(RoutineCompletionSummary)
    case failed(String)

    public var canPause: Bool {
        switch self {
        case .preparing, .guide, .awaitingCamera, .awaitingPose, .countdown, .working, .rest:
            return true
        case .idle, .paused, .complete, .failed:
            return false
        }
    }

    public var needsCamera: Bool {
        switch self {
        case .awaitingCamera, .awaitingPose, .countdown, .working, .rest, .paused:
            return true
        case .idle, .preparing, .guide, .complete, .failed:
            return false
        }
    }

    public var usesGuide: Bool {
        switch self {
        case .preparing, .guide:
            return true
        default:
            return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .idle, .complete, .failed:
            return false
        default:
            return true
        }
    }

    fileprivate var resumable: RoutineRunResumePhase? {
        switch self {
        case .preparing:
            return .preparing
        case let .guide(secondsRemaining):
            return .guide(secondsRemaining: secondsRemaining)
        case let .awaitingCamera(readiness):
            return .awaitingCamera(readiness)
        case let .awaitingPose(message):
            return .awaitingPose(message)
        case let .countdown(secondsRemaining):
            return .countdown(secondsRemaining: secondsRemaining)
        case .working:
            return .working
        case let .rest(secondsRemaining):
            return .rest(secondsRemaining: secondsRemaining)
        case .idle, .paused, .complete, .failed:
            return nil
        }
    }
}

public enum RoutineRunMode: Equatable {
    case fullRoutine
    case startFromBlock
    case practiceBlock
}

@MainActor
public final class RoutineRunner: ObservableObject {
    @Published public private(set) var phase: RoutineRunPhase = .idle
    @Published public private(set) var activeRoutine: ExecutableRoutine?
    @Published public private(set) var cursor = RoutineCursor()
    @Published public private(set) var progressText: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastCompletionReport: WorkoutCompletionReport?
    @Published public private(set) var runScope: WorkoutCompletionScope?

    private let viewModel: AppExerciseSessionViewModel
    private let autoStartsTimers: Bool
    private let now: () -> Date
    private var cameraReadiness: CameraReadiness = .idle
    private var poseReadiness: PosePipelineReadiness = .idle
    private var executionSession: ExerciseExecutionSession?
    private var timer: Timer?
    private var practiceOnly = false
    private var guideOnly = false
    private var completedSets = 0
    private var startedAt: Date?

    public init(viewModel: AppExerciseSessionViewModel, autoStartsTimers: Bool = true, now: @escaping () -> Date = Date.init) {
        self.viewModel = viewModel
        self.autoStartsTimers = autoStartsTimers
        self.now = now
    }

    deinit {
        timer?.invalidate()
    }

    public var currentSet: ExecutableSet? {
        activeRoutine?.set(at: cursor)
    }

    public var currentBlock: ExecutableBlock? {
        activeRoutine?.block(at: cursor)
    }

    public var currentRoutine: WorkoutRoutine? {
        activeRoutine?.routine
    }

    public var activeBlockIndex: Int {
        cursor.blockIndex
    }

    public var blockCount: Int {
        activeRoutine?.blocks.count ?? 0
    }

    public var routineStepText: String? {
        guard let activeRoutine, activeRoutine.blocks.indices.contains(cursor.blockIndex) else {
            return nil
        }
        return "Step \(cursor.blockIndex + 1) of \(activeRoutine.blocks.count)"
    }

    public var setText: String? {
        guard let block = currentBlock else { return nil }
        return "Set \(cursor.setIndex + 1) of \(block.sets.count)"
    }

    public var targetText: String? {
        currentSet?.target.displayText
    }

    public var nextBlockTitle: String? {
        guard let activeRoutine,
              let nextCursor = activeRoutine.nextCursor(after: cursor, practiceOnly: practiceOnly) else {
            return nil
        }
        return activeRoutine.block(at: nextCursor)?.title
    }

    public var isRoutineBackedRun: Bool {
        activeRoutine != nil && runScope == .routine && !practiceOnly
    }

    public var nextExerciseTitle: String? {
        guard let activeRoutine, isRoutineBackedRun else { return nil }
        let nextBlockIndex = cursor.blockIndex + 1
        guard activeRoutine.blocks.indices.contains(nextBlockIndex) else { return nil }
        return activeRoutine.blocks[nextBlockIndex].title
    }

    public var timelineCursor: RoutineCursor {
        if case .rest = phase,
           let nextCursor = activeRoutine?.nextCursor(after: cursor, practiceOnly: practiceOnly) {
            return nextCursor
        }
        return cursor
    }

    public var canTogglePause: Bool {
        phase.canPause || isPaused
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var isGuideOnlyExerciseRun: Bool {
        runScope == .exercise && guideOnly
    }

    public func start(_ routine: WorkoutRoutine, atBlock index: Int = 0) throws {
        try start(routine, cursor: RoutineCursor(blockIndex: index, setIndex: 0), mode: index == 0 ? .fullRoutine : .startFromBlock)
    }

    public func practice(_ routine: WorkoutRoutine, blockIndex: Int) throws {
        guard routine.blocks.indices.contains(blockIndex) else {
            throw AppExerciseSessionError.routineBlockOutOfRange(blockIndex)
        }
        let block = routine.blocks[blockIndex]
        let practiceRoutine = WorkoutRoutine(
            id: "\(routine.id)-practice-\(blockIndex + 1)",
            name: blockPracticeName(for: block, fallback: routine.name),
            description: "Practice from \(routine.name)",
            blocks: [block]
        )
        try start(practiceRoutine, cursor: RoutineCursor(blockIndex: 0, setIndex: 0), mode: .practiceBlock)
    }

    public func start(
        _ routine: WorkoutRoutine,
        cursor requestedCursor: RoutineCursor,
        mode: RoutineRunMode
    ) throws {
        stopTimer()
        viewModel.loadAvailablePresets()

        let compiler = RoutineCompiler { [viewModel] presetID in
            try viewModel.programForPreset(id: presetID)
        }
        let executable = try compiler.compile(routine)
        guard executable.set(at: requestedCursor) != nil else {
            throw AppExerciseSessionError.routineBlockOutOfRange(requestedCursor.blockIndex)
        }

        activeRoutine = executable
        cursor = requestedCursor
        practiceOnly = mode == .practiceBlock
        guideOnly = false
        runScope = mode == .practiceBlock ? .exercise : .routine
        completedSets = 0
        startedAt = now()
        lastError = nil
        lastCompletionReport = nil
        progressText = nil
        try prepareCurrentSet()
        transition(to: .preparing)
    }

    func startExercise(
        exerciseID: String,
        mode: CoachExerciseMode,
        target: SetTarget? = nil
    ) throws {
        stopTimer()
        viewModel.loadAvailablePresets()

        let block: RoutineBlock
        switch target {
        case let .reps(reps):
            block = RoutineBlock(exerciseRef: .preset(id: exerciseID), sets: 1, reps: reps, restSeconds: 0)
        case let .holdSeconds(seconds):
            block = RoutineBlock(exerciseRef: .preset(id: exerciseID), sets: 1, holdSeconds: seconds, restSeconds: 0)
        case .none:
            block = RoutineBlock(exerciseRef: .preset(id: exerciseID), sets: 1, restSeconds: 0)
        }

        let exerciseName = viewModel.availablePresets.first { $0.id == exerciseID }?.name ?? exerciseID
        let routine = WorkoutRoutine(
            id: "standalone-\(exerciseID)",
            name: exerciseName,
            description: "Standalone exercise",
            blocks: [block]
        )
        let compiler = RoutineCompiler { [viewModel] presetID in
            try viewModel.programForPreset(id: presetID)
        }
        let executable = try compiler.compile(routine)

        activeRoutine = executable
        cursor = RoutineCursor()
        practiceOnly = true
        guideOnly = mode == .guide
        runScope = .exercise
        completedSets = 0
        startedAt = guideOnly ? nil : now()
        lastError = nil
        lastCompletionReport = nil
        progressText = nil
        try prepareCurrentSet()

        if guideOnly {
            transition(to: .guide(secondsRemaining: 6), schedulesTimer: false)
        } else {
            transition(to: .preparing)
        }
    }

    public func cancel() {
        stopTimer()
        activeRoutine = nil
        cursor = RoutineCursor()
        executionSession = nil
        progressText = nil
        practiceOnly = false
        guideOnly = false
        completedSets = 0
        startedAt = nil
        runScope = nil
        viewModel.resetLiveSession()
        transition(to: .idle, schedulesTimer: false)
    }

    public func pause() {
        guard let resumable = phase.resumable else { return }
        stopTimer()
        transition(to: .paused(previous: resumable), schedulesTimer: false)
    }

    public func resume() {
        guard case let .paused(previous) = phase else { return }
        transition(to: phase(from: previous))
    }

    public func togglePause() {
        isPaused ? resume() : pause()
    }

    public func skipGuide() {
        switch phase {
        case .preparing, .guide:
            guard !guideOnly else { return }
            enterCameraGate()
        default:
            break
        }
    }

    public func startCurrentExercisePractice() {
        guard activeRoutine != nil, guideOnly else { return }
        guideOnly = false
        startedAt = now()
        enterCameraGate()
    }

    public func replayGuide(seconds: Int = 6) {
        guard activeRoutine != nil else { return }
        transition(to: .guide(secondsRemaining: seconds), schedulesTimer: !guideOnly)
    }

    public func skipRest() {
        guard case .rest = phase else { return }
        advanceAfterCompletedSet()
    }

    public func addRest(seconds: Int) {
        guard case let .rest(secondsRemaining) = phase else { return }
        transition(to: .rest(secondsRemaining: max(0, secondsRemaining + seconds)))
    }

    public func restartCurrentSet() {
        guard activeRoutine != nil else { return }
        do {
            try prepareCurrentSet()
            transition(to: .guide(secondsRemaining: 6))
        } catch {
            fail(error)
        }
    }

    public func skipToNextExercise() {
        guard let activeRoutine, isRoutineBackedRun else { return }
        let nextBlockIndex = cursor.blockIndex + 1
        guard activeRoutine.blocks.indices.contains(nextBlockIndex) else {
            completeRoutine()
            return
        }

        stopTimer()
        cursor = RoutineCursor(blockIndex: nextBlockIndex, setIndex: 0)
        do {
            try prepareCurrentSet()
            transition(to: .preparing)
        } catch {
            fail(error)
        }
    }

    public func updateCameraReadiness(_ readiness: CameraReadiness) {
        cameraReadiness = readiness
        guard activeRoutine != nil else { return }

        switch phase {
        case .awaitingCamera:
            if readiness.isStreaming {
                transition(to: .awaitingPose("Step into frame"))
            } else {
                transition(to: .awaitingCamera(readiness), schedulesTimer: false)
            }
        default:
            break
        }
    }

    public func updatePoseReadiness(_ readiness: PosePipelineReadiness) {
        poseReadiness = readiness
    }

    public func ingest(_ frame: PoseFrame) {
        viewModel.updateLiveOverlay(with: frame)
        guard activeRoutine != nil else {
            viewModel.ingestLiveFrame(frame)
            return
        }

        switch phase {
        case .awaitingPose:
            if currentProgramHasValidPose(frame) {
                poseReadiness = .ready
                beginCountdown(seconds: 3)
            } else {
                poseReadiness = .waitingForFirstPose
                transition(to: .awaitingPose("Move fully into frame"), schedulesTimer: false)
            }
        case .working:
            guard currentProgramHasValidPose(frame) else {
                poseReadiness = .waitingForFirstPose
                return
            }
            guard var session = executionSession else { return }
            let result = session.ingest(frame)
            executionSession = session
            viewModel.applyExerciseFrameResult(result, program: session.program)
            progressText = result.progressText
            if result.completedThisFrame {
                completedSets += 1
                completeCurrentSet()
            }
        default:
            break
        }
    }

    public func timerTick() {
        switch phase {
        case .preparing:
            transition(to: .guide(secondsRemaining: 6))
        case let .guide(secondsRemaining):
            guard !guideOnly else { return }
            if secondsRemaining > 1 {
                transition(to: .guide(secondsRemaining: secondsRemaining - 1))
            } else {
                enterCameraGate()
            }
        case let .countdown(secondsRemaining):
            if secondsRemaining > 1 {
                transition(to: .countdown(secondsRemaining: secondsRemaining - 1))
            } else {
                beginWorking()
            }
        case let .rest(secondsRemaining):
            if secondsRemaining > 1 {
                transition(to: .rest(secondsRemaining: secondsRemaining - 1))
            } else {
                advanceAfterCompletedSet()
            }
        default:
            break
        }
    }

    private func prepareCurrentSet() throws {
        guard let currentSet else { return }
        viewModel.activateProgram(currentSet.program)
        viewModel.resetLiveSession()
        executionSession = try ExerciseExecutionSession(program: currentSet.program, target: currentSet.target)
        progressText = initialProgressText(for: currentSet.target)
    }

    private func enterCameraGate() {
        if cameraReadiness.isStreaming {
            transition(to: .awaitingPose("Step into frame"), schedulesTimer: false)
        } else {
            transition(to: .awaitingCamera(cameraReadiness), schedulesTimer: false)
        }
    }

    private func beginCountdown(seconds: Int) {
        viewModel.resetLiveSession()
        do {
            try prepareCurrentSet()
            transition(to: .countdown(secondsRemaining: max(1, seconds)))
        } catch {
            fail(error)
        }
    }

    private func beginWorking() {
        viewModel.resetLiveSession()
        do {
            try prepareCurrentSet()
            transition(to: .working, schedulesTimer: false)
        } catch {
            fail(error)
        }
    }

    private func completeCurrentSet() {
        guard let activeRoutine else {
            completeRoutine()
            return
        }

        if activeRoutine.nextCursor(after: cursor, practiceOnly: practiceOnly) == nil {
            completeRoutine()
            return
        }

        let restSeconds = currentSet?.restSecondsAfterSet ?? 0
        if restSeconds > 0 {
            transition(to: .rest(secondsRemaining: restSeconds))
        } else {
            advanceAfterCompletedSet()
        }
    }

    private func advanceAfterCompletedSet() {
        guard let activeRoutine,
              let nextCursor = activeRoutine.nextCursor(after: cursor, practiceOnly: practiceOnly) else {
            completeRoutine()
            return
        }

        cursor = nextCursor
        do {
            try prepareCurrentSet()
            transition(to: .preparing)
        } catch {
            fail(error)
        }
    }

    private func completeRoutine() {
        stopTimer()
        let routineName = activeRoutine?.routine.name ?? "Routine"
        let exerciseNames = activeRoutine?.blocks.map(\.title) ?? []
        let completedBlocks = activeRoutine?.blocks.count ?? 0
        let finalProgress = "\(completedSets) \(completedSets == 1 ? "set" : "sets") complete"
        let durationSeconds = max(0, Int(now().timeIntervalSince(startedAt ?? now())))
        let formSignals = viewModel.state.cueText.map { ["Cue: \($0)"] } ?? []
        let cameraIssues: [String]
        switch poseReadiness {
        case let .failed(message), let .degraded(message):
            cameraIssues = [message]
        case let .camera(.failed(message)):
            cameraIssues = [message]
        default:
            cameraIssues = []
        }
        let summary = RoutineCompletionSummary(
            scope: runScope ?? .routine,
            routineName: routineName,
            completedSets: completedSets,
            completedBlocks: completedBlocks,
            completedExerciseNames: exerciseNames,
            durationSeconds: durationSeconds,
            finalProgressText: finalProgress,
            formSignals: formSignals,
            cameraIssues: cameraIssues
        )
        lastCompletionReport = WorkoutCompletionReport(summary: summary)
        activeRoutine = nil
        executionSession = nil
        guideOnly = false
        startedAt = nil
        progressText = summary.displayText
        transition(to: .complete(summary), schedulesTimer: false)
    }

    private func currentProgramHasValidPose(_ frame: PoseFrame) -> Bool {
        guard let program = currentSet?.program else {
            return !AppPoseOverlayState(frame: frame).points.isEmpty
        }

        for landmark in program.setup.requiredLandmarks {
            guard let value = frame.landmark(named: landmark),
                  value.confidence >= program.setup.minVisibility else {
                return false
            }
        }
        return true
    }

    private func transition(to nextPhase: RoutineRunPhase, schedulesTimer: Bool = true) {
        phase = nextPhase
        guard schedulesTimer else { return }
        scheduleTimerIfNeeded(for: nextPhase)
    }

    private func scheduleTimerIfNeeded(for phase: RoutineRunPhase) {
        stopTimer()
        guard autoStartsTimers else { return }

        let interval: TimeInterval?
        switch phase {
        case .preparing:
            interval = 0.45
        case .guide, .countdown, .rest:
            interval = 1
        default:
            interval = nil
        }

        guard let interval else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func fail(_ error: Error) {
        let message = String(describing: error)
        stopTimer()
        lastError = message
        activeRoutine = nil
        executionSession = nil
        transition(to: .failed(message), schedulesTimer: false)
    }

    private func phase(from resumable: RoutineRunResumePhase) -> RoutineRunPhase {
        switch resumable {
        case .preparing:
            return .preparing
        case let .guide(secondsRemaining):
            return .guide(secondsRemaining: secondsRemaining)
        case let .awaitingCamera(readiness):
            return .awaitingCamera(readiness)
        case let .awaitingPose(message):
            return .awaitingPose(message)
        case let .countdown(secondsRemaining):
            return .countdown(secondsRemaining: secondsRemaining)
        case .working:
            return .working
        case let .rest(secondsRemaining):
            return .rest(secondsRemaining: secondsRemaining)
        }
    }

    private func initialProgressText(for target: SetTarget) -> String {
        switch target {
        case let .reps(reps):
            return "0/\(reps) reps"
        case let .holdSeconds(seconds):
            return "0/\(Int(seconds)) sec"
        }
    }

    private func blockPracticeName(for block: RoutineBlock, fallback: String) -> String {
        switch block.exerciseRef {
        case let .preset(id):
            return viewModel.availablePresets.first { $0.id == id }?.name ?? fallback
        case let .inline(program):
            return program.name
        }
    }
}
