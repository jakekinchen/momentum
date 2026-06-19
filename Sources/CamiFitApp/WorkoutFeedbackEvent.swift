import Foundation

public enum WorkoutFeedbackEmphasis: Equatable {
    case counted
    case clean
    case complete
}

public struct WorkoutFeedbackEvent: Equatable, Identifiable {
    public enum Kind: Equatable {
        case repCounted
        case holdComplete
    }

    public let id: UUID
    public let kind: Kind
    public let emphasis: WorkoutFeedbackEmphasis
    public let primaryText: String
    public let detailText: String
    public let spokenText: String
    public let repsCompleted: Int?
    public let targetReps: Int?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        emphasis: WorkoutFeedbackEmphasis,
        primaryText: String,
        detailText: String,
        spokenText: String,
        repsCompleted: Int? = nil,
        targetReps: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.emphasis = emphasis
        self.primaryText = primaryText
        self.detailText = detailText
        self.spokenText = spokenText
        self.repsCompleted = repsCompleted
        self.targetReps = targetReps
    }

    public static func repCounted(
        repsCompleted: Int,
        targetReps: Int?,
        cueText: String?,
        isSetComplete: Bool
    ) -> WorkoutFeedbackEvent {
        let hasCue = cueText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let detail: String
        if isSetComplete {
            detail = "Set complete"
        } else if let targetReps {
            detail = "\(min(repsCompleted, targetReps)) / \(targetReps) reps"
        } else {
            detail = "Rep counted"
        }

        return WorkoutFeedbackEvent(
            kind: .repCounted,
            emphasis: isSetComplete ? .complete : (hasCue ? .counted : .clean),
            primaryText: "\(repsCompleted)",
            detailText: detail,
            spokenText: isSetComplete ? "\(repsCompleted). Set complete." : "\(repsCompleted)",
            repsCompleted: repsCompleted,
            targetReps: targetReps
        )
    }

    public static func holdComplete(heldSeconds: Double) -> WorkoutFeedbackEvent {
        WorkoutFeedbackEvent(
            kind: .holdComplete,
            emphasis: .complete,
            primaryText: "Done",
            detailText: "\(SetTarget.formatSeconds(heldSeconds))s hold",
            spokenText: "Hold complete"
        )
    }
}
