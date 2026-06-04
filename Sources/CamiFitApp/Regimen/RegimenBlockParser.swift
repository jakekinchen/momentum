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
