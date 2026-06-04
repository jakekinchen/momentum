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
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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

        guard let frame = sampleFrame() else { return .failure(.noSampleFrame) }
        do {
            var processor = try FrameSignalProcessor(program: program)
            _ = processor.process(frame: frame)
        } catch {
            return .failure(.evaluation(String(describing: error)))
        }
        return .success(program)
    }

    static func sampleFrame() -> PoseFrame? {
        guard let url = Bundle.module.url(forResource: "synthetic_squat_demo", withExtension: "jsonl", subdirectory: "Demo"),
              let frames = try? MediaPipePoseJSONLDecoder.decode(contentsOf: url) else { return nil }
        return frames.first
    }
}
