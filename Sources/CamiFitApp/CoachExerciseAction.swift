import Foundation

enum CoachExerciseMode: String, Codable, Equatable {
    case guide
    case camera
    case matchForm = "match_form"

    var displayText: String {
        switch self {
        case .guide:
            return "Guide"
        case .camera:
            return "Camera"
        case .matchForm:
            return "Match Form"
        }
    }
}

struct CoachExerciseTarget: Codable, Equatable {
    var reps: Int?
    var holdSeconds: Double?

    var setTarget: SetTarget? {
        if let reps {
            return .reps(reps)
        }
        if let holdSeconds {
            return .holdSeconds(holdSeconds)
        }
        return nil
    }

    var hasConflictingTargets: Bool {
        reps != nil && holdSeconds != nil
    }
}

struct CoachExerciseAction: Codable, Equatable {
    var schemaVersion: Int
    var tool: String
    var exerciseID: String
    var mode: CoachExerciseMode
    var target: CoachExerciseTarget?
    var reason: String?

    init(
        schemaVersion: Int = 1,
        tool: String = "activate_exercise",
        exerciseID: String,
        mode: CoachExerciseMode,
        target: CoachExerciseTarget? = nil,
        reason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.tool = tool
        self.exerciseID = exerciseID
        self.mode = mode
        self.target = target
        self.reason = reason
    }
}

enum CoachActionParser {
    static func parse(message: String) -> [CoachExerciseAction] {
        extractActionJSONBlocks(from: message).compactMap { json in
            guard let data = json.data(using: .utf8),
                  let action = try? JSONDecoder().decode(CoachExerciseAction.self, from: data),
                  action.schemaVersion == 1,
                  action.tool == "activate_exercise" else {
                return nil
            }
            return action
        }
    }

    static func displayText(removingActionBlocks text: String) -> String {
        var output: [String] = []
        var isSkipping = false

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSkipping {
                if trimmed == "```" {
                    isSkipping = false
                }
                continue
            }
            if trimmed.lowercased() == "```future-coach-action" {
                isSkipping = true
                continue
            }
            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    private static func extractActionJSONBlocks(from text: String) -> [String] {
        var blocks: [String] = []
        var isCapturing = false
        var buffer: [String] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isCapturing {
                if trimmed.lowercased() == "```future-coach-action" {
                    isCapturing = true
                    buffer = []
                }
                continue
            }

            if trimmed == "```" {
                blocks.append(buffer.joined(separator: "\n"))
                isCapturing = false
                buffer = []
            } else {
                buffer.append(line)
            }
        }

        return blocks
    }
}

@MainActor
final class ExerciseModeController: ObservableObject {
    @Published private(set) var current: ExerciseModeRequest?

    func activate(exerciseID: String, mode: CoachExerciseMode, reason: String?) {
        current = ExerciseModeRequest(exerciseID: exerciseID, mode: mode, reason: reason)
    }

    func clear() {
        current = nil
    }
}

struct ExerciseModeRequest: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: String
    let mode: CoachExerciseMode
    let reason: String?
}

enum CoachActionStatus: Equatable {
    case succeeded
    case failed
}

struct CoachActionResult: Identifiable, Equatable {
    let id = UUID()
    let status: CoachActionStatus
    let title: String
    let detail: String
    let action: CoachExerciseAction
}

@MainActor
final class CoachActionDispatcher {
    private let viewModel: AppExerciseSessionViewModel
    private let routineRunner: RoutineRunner
    private let modeController: ExerciseModeController

    init(
        viewModel: AppExerciseSessionViewModel,
        routineRunner: RoutineRunner,
        modeController: ExerciseModeController
    ) {
        self.viewModel = viewModel
        self.routineRunner = routineRunner
        self.modeController = modeController
    }

    func apply(_ action: CoachExerciseAction) -> CoachActionResult {
        guard action.tool == "activate_exercise" else {
            return failure("Unsupported coach action: \(action.tool)", action: action)
        }

        if action.target?.hasConflictingTargets == true {
            return failure("Exercise action cannot request reps and holdSeconds at the same time.", action: action)
        }

        do {
            try routineRunner.startExercise(
                exerciseID: action.exerciseID,
                mode: action.mode,
                target: action.target?.setTarget
            )
        } catch {
            return failure("Could not activate \(action.exerciseID): \(error)", action: action)
        }

        modeController.activate(
            exerciseID: action.exerciseID,
            mode: action.mode,
            reason: action.reason
        )

        return CoachActionResult(
            status: .succeeded,
            title: action.mode.displayText,
            detail: successDetail(for: action),
            action: action
        )
    }

    private func successDetail(for action: CoachExerciseAction) -> String {
        switch action.mode {
        case .guide:
            return "Showing the guide for \(action.exerciseID)."
        case .camera:
            return "Starting camera practice for \(action.exerciseID)."
        case .matchForm:
            return "Starting form match for \(action.exerciseID)."
        }
    }

    private func failure(_ detail: String, action: CoachExerciseAction) -> CoachActionResult {
        CoachActionResult(
            status: .failed,
            title: "Coach action unavailable",
            detail: detail,
            action: action
        )
    }
}
