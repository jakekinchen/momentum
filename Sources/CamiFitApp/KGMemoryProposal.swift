import Foundation
import KGKit

struct KGMemoryOperationProposal: Equatable {
    let operationType: GraphOperationType
    let constraintType: String
    let value: String
    let sourceText: String
    let hard: Bool
    let reason: String?
}

struct KGMemoryChatArtifact: Identifiable, Equatable {
    enum Status: Equatable {
        case saved
        case failed
    }

    let id = UUID()
    let status: Status
    let title: String
    let detail: String
}

enum KGMemoryProposalParser {
    private static let operationFenceTags = [
        "future-kg-operation",
        "camifit-kg-operation"
    ]

    static func parse(message: String) -> [KGMemoryOperationProposal] {
        fencedBlocks(in: message).compactMap(decodeProposal)
    }

    static func displayText(removingProposalBlocks message: String) -> String {
        var output: [String] = []
        var isSkipping = false

        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSkipping {
                if trimmed == "```" {
                    isSkipping = false
                }
            } else if isOperationFence(trimmed) {
                isSkipping = true
            } else {
                output.append(line)
            }
        }

        return output
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fencedBlocks(in message: String) -> [String] {
        var blocks: [String] = []
        var isCapturing = false
        var current: [String] = []

        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCapturing {
                if trimmed == "```" {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                    isCapturing = false
                } else {
                    current.append(line)
                }
            } else if isOperationFence(trimmed) {
                isCapturing = true
            }
        }

        return blocks
    }

    private static func isOperationFence(_ trimmedLine: String) -> Bool {
        let lowercased = trimmedLine.lowercased()
        return operationFenceTags.contains { lowercased.hasPrefix("```\($0)") }
    }

    private static func decodeProposal(_ text: String) -> KGMemoryOperationProposal? {
        guard let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode(RawProposal.self, from: data),
              let operationType = GraphOperationType(rawValue: raw.operationType),
              operationType == .addMedicalConstraint,
              raw.constraintType == "BodyRegion",
              let value = cleaned(raw.value),
              let sourceText = cleaned(raw.sourceText) else {
            return nil
        }
        return KGMemoryOperationProposal(
            operationType: operationType,
            constraintType: raw.constraintType,
            value: value,
            sourceText: sourceText,
            hard: raw.hard ?? true,
            reason: cleaned(raw.reason)
        )
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct RawProposal: Decodable {
        let operationType: String
        let constraintType: String
        let value: String?
        let sourceText: String?
        let hard: Bool?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case operationType = "operation_type"
            case constraintType = "constraint_type"
            case value
            case sourceText = "source_text"
            case hard
            case reason
        }
    }
}

enum KGMemoryChatBridge {
    static func applyProposals(in assistantText: String,
                               sourceUserText: String,
                               store: KGMemoryStore?) -> [KGMemoryChatArtifact] {
        let proposals = KGMemoryProposalParser.parse(message: assistantText)
        guard !proposals.isEmpty else { return [] }
        guard let store else {
            return proposals.map {
                KGMemoryChatArtifact(
                    status: .failed,
                    title: "Memory not saved",
                    detail: "No app-owned memory store is available for \($0.displayTitle)."
                )
            }
        }

        return proposals.map { proposal in
            do {
                let item = try store.addHealthMemory(
                    value: proposal.value,
                    sourceText: proposal.sourceText.isEmpty ? sourceUserText : proposal.sourceText,
                    reason: proposal.reason ?? "Coach captured this health/safety memory from chat.",
                    actor: .agent
                )
                return KGMemoryChatArtifact(
                    status: .saved,
                    title: "Memory saved",
                    detail: "\(item.title) health/safety memory added to the local KG."
                )
            } catch {
                return KGMemoryChatArtifact(
                    status: .failed,
                    title: "Memory not saved",
                    detail: String(describing: error)
                )
            }
        }
    }

    static func coachContext(from store: KGMemoryStore?) -> String? {
        guard let store else { return nil }
        let active = store.state.items.filter { $0.category == .healthSafety && $0.status == .active }
        guard !active.isEmpty else { return nil }
        let facts = active.map { "- \($0.title): \($0.sourceText)" }.joined(separator: "\n")
        return """
        Future Coach local KG fact cards for this user:
        \(facts)

        Treat these as active health/safety constraints when answering. If a workout would stress a listed body region, avoid it or suggest a gentler alternative. Do not claim you wrote the KG yourself; the Future Coach app owns KG writes.
        """
    }
}

private extension KGMemoryOperationProposal {
    var displayTitle: String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
