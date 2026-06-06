import CamiFitEngine
import Foundation

struct RoutinePresentationSummary: Equatable {
    let exerciseCount: Int
    let setCount: Int
    let estimatedSeconds: Int?
    let isRunnable: Bool
    let availabilityText: String?

    var exerciseCountText: String {
        "\(exerciseCount) \(exerciseCount == 1 ? "exercise" : "exercises")"
    }

    var setCountText: String {
        "\(setCount) \(setCount == 1 ? "set" : "sets")"
    }

    var durationText: String {
        RoutinePresentation.durationText(seconds: estimatedSeconds)
    }

    var compactDetailText: String {
        let base = "\(exerciseCountText) · \(durationText)"
        guard !isRunnable else { return base }
        return "\(base) · Unavailable"
    }
}

struct ExercisePresentationSummary: Equatable {
    let kindText: String
    let targetText: String
    let estimatedSetText: String
    let setupText: String
    let trackingText: String
    let cueTexts: [String]
}

enum RoutinePresentation {
    static let guideSecondsPerSet = 6
    static let countdownSecondsPerSet = 3
    static let secondsPerRep = 3

    static func summary(for routine: WorkoutRoutine, compiler: RoutineCompiler) -> RoutinePresentationSummary {
        do {
            let executable = try compiler.compile(routine)
            return RoutinePresentationSummary(
                exerciseCount: executable.blocks.count,
                setCount: executable.allSets.count,
                estimatedSeconds: estimatedSeconds(for: executable),
                isRunnable: true,
                availabilityText: nil
            )
        } catch {
            return RoutinePresentationSummary(
                exerciseCount: routine.blocks.count,
                setCount: routine.blocks.reduce(0) { $0 + max(0, $1.sets) },
                estimatedSeconds: fallbackEstimatedSeconds(for: routine),
                isRunnable: false,
                availabilityText: userFacingErrorText(String(describing: error))
            )
        }
    }

    static func summary(for program: ExerciseProgram) -> ExercisePresentationSummary {
        let target = SetTarget.defaultTarget(for: program)
        var cueTexts: [String] = []
        for cue in program.formRules.map(\.cue) where !cueTexts.contains(cue) {
            cueTexts.append(cue)
        }

        return ExercisePresentationSummary(
            kindText: program.hold == nil ? "Counts reps" : "Timed hold",
            targetText: target?.displayText ?? "Target unavailable",
            estimatedSetText: durationText(seconds: target.map(workSeconds(for:))),
            setupText: formattedView(program.setup.requiredView.rawValue),
            trackingText: "\(program.setup.requiredLandmarks.count) landmarks",
            cueTexts: Array(cueTexts.prefix(3))
        )
    }

    static func targetText(sets: Int, target: SetTarget) -> String {
        let setText = "\(sets) \(sets == 1 ? "set" : "sets")"
        return "\(setText) x \(target.displayText)"
    }

    static func restText(seconds: Int) -> String {
        seconds > 0 ? "\(seconds)s rest" : "No rest"
    }

    static func durationText(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Estimate unavailable" }
        if seconds < 60 {
            return "About \(seconds)s"
        }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return "About \(minutes) min"
    }

    static func userFacingErrorText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "Block", with: "Exercise")
            .replacingOccurrences(of: "block", with: "exercise")
    }

    static func estimatedSeconds(for executable: ExecutableRoutine) -> Int {
        var total = 0
        let sets = executable.allSets
        for (offset, set) in sets.enumerated() {
            total += guideSecondsPerSet + countdownSecondsPerSet + workSeconds(for: set.target)
            if offset < sets.count - 1 {
                total += set.restSecondsAfterSet
            }
        }
        return total
    }

    static func estimatedSeconds(for block: ExecutableBlock) -> Int {
        let perSet = guideSecondsPerSet + countdownSecondsPerSet + workSeconds(for: block.target)
        let betweenSetRest = max(0, block.sets.count - 1) * block.restSeconds
        return block.sets.count * perSet + betweenSetRest
    }

    static func workSeconds(for target: SetTarget) -> Int {
        switch target {
        case let .reps(reps):
            return max(1, reps) * secondsPerRep
        case let .holdSeconds(seconds):
            return max(1, Int(ceil(seconds)))
        }
    }

    private static func fallbackEstimatedSeconds(for routine: WorkoutRoutine) -> Int? {
        var total = 0
        var hasAnyTarget = false
        for (offset, block) in routine.blocks.enumerated() {
            guard let target = fallbackTarget(for: block), block.sets > 0 else { continue }
            hasAnyTarget = true
            total += block.sets * (guideSecondsPerSet + countdownSecondsPerSet + workSeconds(for: target))
            if offset < routine.blocks.count - 1 {
                total += max(0, block.restSeconds ?? 0)
            }
        }
        return hasAnyTarget ? total : nil
    }

    private static func fallbackTarget(for block: RoutineBlock) -> SetTarget? {
        if let reps = block.reps, reps > 0 {
            return .reps(reps)
        }
        if let holdSeconds = block.holdSeconds, holdSeconds > 0 {
            return .holdSeconds(holdSeconds)
        }
        return nil
    }

    private static func formattedView(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

extension SetTarget {
    static func defaultTarget(for program: ExerciseProgram) -> SetTarget? {
        if let hold = program.hold {
            return .holdSeconds(program.set.targetSeconds ?? hold.targetSeconds)
        }
        if let targetReps = program.set.targetReps {
            return .reps(targetReps)
        }
        if let targetSeconds = program.set.targetSeconds {
            return .holdSeconds(targetSeconds)
        }
        return nil
    }
}
