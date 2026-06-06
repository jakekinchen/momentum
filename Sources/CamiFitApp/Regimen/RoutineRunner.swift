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
    public let routineName: String
    public let completedSets: Int
    public let completedBlocks: Int

    public var displayText: String {
        "\(completedSets) \(completedSets == 1 ? "set" : "sets") complete"
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

    private let viewModel: AppExerciseSessionViewModel
    private let autoStartsTimers: Bool
    private var cameraReadiness: CameraReadiness = .idle
    private var poseReadiness: PosePipelineReadiness = .idle
    private var executionSession: ExerciseExecutionSession?
    private var timer: Timer?
    private var practiceOnly = false
    private var completedSets = 0

    public init(viewModel: AppExerciseSessionViewModel, autoStartsTimers: Bool = true) {
        self.viewModel = viewModel
        self.autoStartsTimers = autoStartsTimers
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

    public var canTogglePause: Bool {
        phase.canPause || isPaused
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
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
        completedSets = 0
        lastError = nil
        progressText = nil
        try prepareCurrentSet()
        transition(to: .preparing)
    }

    public func cancel() {
        stopTimer()
        activeRoutine = nil
        cursor = RoutineCursor()
        executionSession = nil
        progressText = nil
        practiceOnly = false
        completedSets = 0
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
            enterCameraGate()
        default:
            break
        }
    }

    public func replayGuide(seconds: Int = 6) {
        guard activeRoutine != nil else { return }
        transition(to: .guide(secondsRemaining: seconds))
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
        let summary = RoutineCompletionSummary(
            routineName: activeRoutine?.routine.name ?? "Routine",
            completedSets: completedSets,
            completedBlocks: activeRoutine?.blocks.count ?? 0
        )
        activeRoutine = nil
        executionSession = nil
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
