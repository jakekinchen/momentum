import Foundation

enum ChatStreamingDisplayFilter {
    private static let artifactFenceOpenings = [
        "```future-routine",
        "```camifit-routine",
        "```future-exercise",
        "```camifit-exercise",
        "```future-coach-action",
        "```future-kg-operation",
        "```camifit-kg-operation"
    ]

    static func displayText(for rawText: String) -> String {
        var output: [String] = []
        let lines = rawText.components(separatedBy: "\n")
        var isSkippingArtifactBlock = false

        let lastIndex = lines.index(before: lines.endIndex)
        for index in lines.indices {
            let line = lines[index]
            let trimmed = normalized(line)

            if isSkippingArtifactBlock {
                if trimmed == "```" {
                    isSkippingArtifactBlock = false
                }
                continue
            }

            if isArtifactOpening(trimmed) {
                isSkippingArtifactBlock = true
                continue
            }

            if index == lastIndex, isPotentialArtifactOpeningPrefix(trimmed) {
                continue
            }

            output.append(line)
        }

        return collapsedBlankRuns(output.joined(separator: "\n"))
    }

    private static func isArtifactOpening(_ trimmedLine: String) -> Bool {
        artifactFenceOpenings.contains(trimmedLine)
    }

    private static func isPotentialArtifactOpeningPrefix(_ trimmedLine: String) -> Bool {
        guard !trimmedLine.isEmpty else { return false }
        return artifactFenceOpenings.contains { opening in
            opening.hasPrefix(trimmedLine)
        }
    }

    private static func normalized(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func collapsedBlankRuns(_ text: String) -> String {
        var output: [String] = []
        var blankLineCount = 0

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankLineCount += 1
                if blankLineCount <= 1 {
                    output.append(line)
                }
            } else {
                blankLineCount = 0
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }
}

extension ChatMessage {
    var shouldShowBubble: Bool {
        role == .user || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
