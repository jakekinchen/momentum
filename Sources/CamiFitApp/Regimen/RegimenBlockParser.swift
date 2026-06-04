import CamiFitEngine
import Foundation

enum RegimenBlockKind: String, Equatable {
    case exercise = "camifit-exercise"
    case routine = "camifit-routine"
}

struct RegimenRawBlock: Equatable {
    let kind: RegimenBlockKind
    let json: String
}

enum RegimenBlockParser {
    static func extractBlocks(from text: String) -> [RegimenRawBlock] {
        var blocks: [RegimenRawBlock] = []
        let lines = text.components(separatedBy: "\n")
        var current: RegimenBlockKind?
        var buffer: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if current == nil {
                if trimmed == "```camifit-exercise" { current = .exercise; buffer = [] }
                else if trimmed == "```camifit-routine" { current = .routine; buffer = [] }
            } else if trimmed == "```" {
                if let kind = current {
                    blocks.append(RegimenRawBlock(kind: kind, json: buffer.joined(separator: "\n")))
                }
                current = nil
                buffer = []
            } else {
                buffer.append(line)
            }
        }
        return blocks
    }
}

enum RegimenValidationError: Error, Equatable {
    case decode(String)
    case evaluation(String)
    case noSampleFrame
}

extension RegimenBlockParser {
    static func validateExercise(json: String) -> Result<ExerciseProgram, RegimenValidationError> {
        guard let data = json.data(using: .utf8) else { return .failure(.decode("not utf8")) }
        let program: ExerciseProgram
        do { program = try ProgramLoader.load(data: data) }
        catch { return .failure(.decode(String(describing: error))) }

        if let error = validate(program: program) { return .failure(error) }
        return .success(program)
    }

    /// Dry-run an already-decoded program; returns nil if it evaluates without error.
    static func validate(program: ExerciseProgram) -> RegimenValidationError? {
        guard let frame = sampleFrame() else { return .noSampleFrame }
        do {
            var processor = try FrameSignalProcessor(program: program)
            _ = processor.process(frame: frame)
        } catch {
            return .evaluation(String(describing: error))
        }
        return nil
    }

    static func sampleFrame() -> PoseFrame? {
        guard let url = Bundle.module.url(forResource: "synthetic_squat_demo", withExtension: "jsonl", subdirectory: "Demo"),
              let frames = try? MediaPipePoseJSONLDecoder.decode(contentsOf: url) else { return nil }
        return frames.first
    }
}

enum RegimenResult: Equatable {
    case exercise(ExerciseProgram)
    case routine(WorkoutRoutine)
    case invalid(kind: RegimenBlockKind, message: String)
}

extension RegimenBlockParser {
    static func parse(message: String) -> [RegimenResult] {
        extractBlocks(from: message).map { block in
            switch block.kind {
            case .exercise:
                switch validateExercise(json: block.json) {
                case let .success(program): return .exercise(program)
                case let .failure(error): return .invalid(kind: .exercise, message: String(describing: error))
                }
            case .routine:
                guard let data = block.json.data(using: .utf8),
                      let routine = try? JSONDecoder().decode(WorkoutRoutine.self, from: data) else {
                    return .invalid(kind: .routine, message: "Could not parse routine JSON.")
                }
                return .routine(routine)
            }
        }
    }
}
