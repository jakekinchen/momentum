import CamiFitEngine
import Foundation

public struct ExerciseFrameResult: Equatable {
    public let trace: EngineTraceFrame
    public let target: SetTarget
    public let repsCompleted: Int
    public let holdSeconds: Double
    public let completedThisFrame: Bool
    public let isComplete: Bool

    public var progressText: String {
        switch target {
        case let .reps(targetReps):
            return "\(min(repsCompleted, targetReps))/\(targetReps) reps"
        case let .holdSeconds(targetSeconds):
            return "\(Int(min(holdSeconds, targetSeconds)))/\(Int(targetSeconds)) sec"
        }
    }

    public var cueText: String? {
        trace.formSummary.selectedCue
    }

    public var scoreText: String? {
        trace.formSummary.score.map { String(format: "%.3f", $0) }
    }

    public var diagnosticText: String? {
        if let invalidReason = trace.rep.invalidReason {
            return invalidReason
        }
        if trace.hold?.valid == false {
            return trace.hold?.notAccumulatingReason
        }
        return nil
    }
}

public struct ExerciseExecutionSession {
    public let program: ExerciseProgram
    public let target: SetTarget
    private var recorder: EngineTraceRecorder
    private var repsCompleted = 0
    private var completed = false

    public init(program: ExerciseProgram, target: SetTarget) throws {
        self.program = program
        self.target = target
        recorder = try EngineTraceRecorder(program: program)
    }

    public mutating func ingest(_ frame: PoseFrame) -> ExerciseFrameResult {
        let trace = recorder.record(frame: frame)
        let completedThisFrame: Bool

        switch target {
        case let .reps(targetReps):
            if !completed, trace.rep.countedThisFrame {
                repsCompleted = min(targetReps, repsCompleted + 1)
            }
            completedThisFrame = !completed && repsCompleted >= targetReps
            if completedThisFrame {
                completed = true
            }

        case let .holdSeconds(targetSeconds):
            let heldSeconds = trace.hold?.heldSeconds ?? 0
            completedThisFrame = !completed && heldSeconds >= targetSeconds
            if completedThisFrame {
                completed = true
            }
        }

        return ExerciseFrameResult(
            trace: trace,
            target: target,
            repsCompleted: repsCompleted,
            holdSeconds: trace.hold?.heldSeconds ?? 0,
            completedThisFrame: completedThisFrame,
            isComplete: completed
        )
    }
}

