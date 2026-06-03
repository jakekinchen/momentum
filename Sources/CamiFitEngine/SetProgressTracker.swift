import Foundation

public struct SetProgressSnapshot: Equatable, CustomStringConvertible {
    public let repsCompleted: Int
    public let targetReps: Int?
    public let isComplete: Bool
    public let completedThisFrame: Bool

    public var description: String {
        [
            "reps=\(repsCompleted)/\(targetReps.map(String.init) ?? "nil")",
            "complete=\(isComplete)",
            "completed_this_frame=\(completedThisFrame)"
        ].joined(separator: " ")
    }
}

public struct SetProgressTracker {
    private let set: SetConfig
    private var repsCompleted = 0
    private var hasCompleted = false

    public init(program: ExerciseProgram) {
        self.init(set: program.set)
    }

    public init(set: SetConfig) {
        self.set = set
    }

    public var snapshot: SetProgressSnapshot {
        makeSnapshot(completedThisFrame: false)
    }

    public mutating func advance(repSnapshot: RepStateSnapshot) -> SetProgressSnapshot {
        guard repSnapshot.countedThisFrame else {
            return makeSnapshot(completedThisFrame: false)
        }

        if let targetReps = set.targetReps, repsCompleted >= targetReps {
            hasCompleted = true
            return makeSnapshot(completedThisFrame: false)
        }

        repsCompleted += 1

        let completedThisFrame: Bool
        if let targetReps = set.targetReps, repsCompleted >= targetReps {
            repsCompleted = targetReps
            completedThisFrame = !hasCompleted
            hasCompleted = true
        } else {
            completedThisFrame = false
        }

        return makeSnapshot(completedThisFrame: completedThisFrame)
    }

    private func makeSnapshot(completedThisFrame: Bool) -> SetProgressSnapshot {
        SetProgressSnapshot(
            repsCompleted: repsCompleted,
            targetReps: set.targetReps,
            isComplete: isComplete,
            completedThisFrame: completedThisFrame
        )
    }

    private var isComplete: Bool {
        guard let targetReps = set.targetReps else {
            return false
        }

        return repsCompleted >= targetReps
    }
}
