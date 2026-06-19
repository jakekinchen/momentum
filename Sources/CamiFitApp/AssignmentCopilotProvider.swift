import Foundation
import KGKit

protocol AssignmentCopilotProviding: AnyObject {
    func factCard(for prompt: String) throws -> AssignmentCopilotFactCard
    func factCard(for request: AssignmentCopilotRequest) throws -> AssignmentCopilotFactCard
}

enum AssignmentCopilotQuery: String, Codable, Equatable {
    case brief
    case adherence
    case sleep
    case changed
    case messagePattern = "message_pattern"
    case churn
}

struct AssignmentCopilotRequest: Equatable {
    let query: AssignmentCopilotQuery
    let prompt: String?
    let reason: String?

    init(query: AssignmentCopilotQuery, prompt: String? = nil, reason: String? = nil) {
        self.query = query
        self.prompt = prompt
        self.reason = reason
    }
}

enum AssignmentCopilotRequestParser {
    private static let requestFenceTags = [
        "future-kg-fact-request"
    ]

    static func parse(message: String) -> [AssignmentCopilotRequest] {
        fencedBlocks(in: message).compactMap(decodeRequest)
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
            } else if isRequestFence(trimmed) {
                isCapturing = true
            }
        }

        return blocks
    }

    private static func isRequestFence(_ trimmedLine: String) -> Bool {
        let lowercased = trimmedLine.lowercased()
        return requestFenceTags.contains { lowercased == "```\($0)" }
    }

    private static func decodeRequest(_ text: String) -> AssignmentCopilotRequest? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawRequest.self, from: data),
              raw.schemaVersion == 1,
              raw.tool == "lookup_member_fact" else {
            return nil
        }

        return AssignmentCopilotRequest(
            query: raw.query,
            prompt: cleaned(raw.prompt),
            reason: cleaned(raw.reason)
        )
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct RawRequest: Decodable {
        let schemaVersion: Int
        let tool: String
        let query: AssignmentCopilotQuery
        let prompt: String?
        let reason: String?
    }
}

struct AssignmentCopilotChartPoint: Identifiable, Equatable {
    let id: String
    let label: String
    let value: Double
}

struct AssignmentCopilotFactCard: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let evidenceNodeIDs: [String]
    let chart: [AssignmentCopilotChartPoint]
    let hasSupportingFact: Bool

    static func noSupportingFact(prompt: String) -> AssignmentCopilotFactCard {
        AssignmentCopilotFactCard(
            id: "no-supporting-fact-\(prompt.hashValue)",
            title: "No supporting fact",
            summary: "The assignment member graph does not contain a supporting fact for that request.",
            evidenceNodeIDs: [],
            chart: [],
            hasSupportingFact: false
        )
    }
}

final class AssignmentCopilotProvider: AssignmentCopilotProviding {
    private let memberGraphData: () throws -> Data

    init(memberGraphData: @escaping () throws -> Data = { try ArtifactLoader.assessmentMemberGraphData() }) {
        self.memberGraphData = memberGraphData
    }

    func factCard(for prompt: String) throws -> AssignmentCopilotFactCard {
        guard let route = Self.route(prompt) else {
            return .noSupportingFact(prompt: prompt)
        }
        return try factCard(for: AssignmentCopilotRequest(query: route, prompt: prompt))
    }

    func factCard(for request: AssignmentCopilotRequest) throws -> AssignmentCopilotFactCard {
        let graph = try MemberGraph(data: memberGraphData())
        let prompt = request.prompt ?? request.query.rawValue
        switch request.query {
        case .brief:
            return graph.briefCard() ?? .noSupportingFact(prompt: prompt)
        case .adherence:
            return graph.adherenceCard() ?? .noSupportingFact(prompt: prompt)
        case .sleep:
            return graph.sleepCard() ?? .noSupportingFact(prompt: prompt)
        case .changed:
            return graph.changedSinceLastWeekCard() ?? .noSupportingFact(prompt: prompt)
        case .messagePattern:
            return graph.messagePatternCard() ?? .noSupportingFact(prompt: prompt)
        case .churn:
            return graph.churnCard() ?? .noSupportingFact(prompt: prompt)
        }
    }

    private static func route(_ prompt: String) -> AssignmentCopilotQuery? {
        let text = prompt.lowercased()
        if text.contains("brief") || text.contains("morning") { return .brief }
        if text.contains("adherence") || text.contains("completion") { return .adherence }
        if text.contains("sleep") { return .sleep }
        if text.contains("changed") || text.contains("last week") { return .changed }
        if text.contains("message") || text.contains("chat pattern") { return .messagePattern }
        if text.contains("churn") || text.contains("risk") { return .churn }
        return nil
    }
}

private struct MemberGraph {
    let nodes: [[String: Any]]

    init(data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        nodes = root?["nodes"] as? [[String: Any]] ?? []
    }

    func briefCard() -> AssignmentCopilotFactCard? {
        guard let node = first(type: "CoachBrief"),
              let text = props(node)["text"] as? String else { return nil }
        return AssignmentCopilotFactCard(
            id: "brief",
            title: "Morning brief",
            summary: text,
            evidenceNodeIDs: [id(node)],
            chart: [],
            hasSupportingFact: true
        )
    }

    func adherenceCard() -> AssignmentCopilotFactCard? {
        let observations = all(type: "AdherenceObservation")
            .compactMap { node -> (String, Int, String)? in
                let p = props(node)
                guard let week = p["week_start"] as? String,
                      let pct = p["pct"] as? Int else { return nil }
                return (week, pct, id(node))
            }
            .sorted { $0.0 < $1.0 }
        guard !observations.isEmpty else { return nil }
        let last = observations.last!
        return AssignmentCopilotFactCard(
            id: "adherence",
            title: "Adherence trend",
            summary: "Latest weekly completion is \(last.1)% for week \(last.0).",
            evidenceNodeIDs: observations.map(\.2),
            chart: observations.map { AssignmentCopilotChartPoint(id: $0.0, label: $0.0, value: Double($0.1)) },
            hasSupportingFact: true
        )
    }

    func sleepCard() -> AssignmentCopilotFactCard? {
        guard let node = all(type: "BiomarkerObservation").first(where: { props($0)["metric"] as? String == "sleep_hours" }),
              let rawValues = props(node)["values"] as? [Any] else { return nil }
        let values = rawValues.compactMap { value -> Double? in
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let value = value as? NSNumber { return value.doubleValue }
            return nil
        }
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(max(1, values.count))
        return AssignmentCopilotFactCard(
            id: "sleep",
            title: "Sleep this week",
            summary: String(format: "Average sleep is %.1f hours across the last %d days.", average, values.count),
            evidenceNodeIDs: [id(node)],
            chart: values.enumerated().map {
                AssignmentCopilotChartPoint(id: "sleep-\($0.offset)", label: "Day \($0.offset + 1)", value: $0.element)
            },
            hasSupportingFact: true
        )
    }

    func changedSinceLastWeekCard() -> AssignmentCopilotFactCard? {
        let observations = all(type: "AdherenceObservation")
            .compactMap { node -> (String, Int, String)? in
                let p = props(node)
                guard let week = p["week_start"] as? String,
                      let pct = p["pct"] as? Int else { return nil }
                return (week, pct, id(node))
            }
            .sorted { $0.0 < $1.0 }
        guard observations.count >= 2 else { return nil }
        let previous = observations[observations.count - 2]
        let current = observations[observations.count - 1]
        let delta = current.1 - previous.1
        return AssignmentCopilotFactCard(
            id: "changed",
            title: "Changed since last week",
            summary: "Weekly completion changed by \(delta) points from \(previous.0) to \(current.0).",
            evidenceNodeIDs: [previous.2, current.2],
            chart: [
                AssignmentCopilotChartPoint(id: previous.0, label: previous.0, value: Double(previous.1)),
                AssignmentCopilotChartPoint(id: current.0, label: current.0, value: Double(current.1)),
            ],
            hasSupportingFact: true
        )
    }

    func messagePatternCard() -> AssignmentCopilotFactCard? {
        let messages = all(type: "Message")
        guard !messages.isEmpty else { return nil }
        return AssignmentCopilotFactCard(
            id: "message-pattern",
            title: "Message pattern",
            summary: "The graph contains \(messages.count) recent Jordan chat messages with source-backed text and timestamps.",
            evidenceNodeIDs: messages.map(id),
            chart: [],
            hasSupportingFact: true
        )
    }

    func churnCard() -> AssignmentCopilotFactCard? {
        guard let node = first(type: "ChurnSignal") else { return nil }
        let p = props(node)
        let level = p["risk_level"] as? String ?? "unknown"
        let reasons = (p["reasons"] as? [String] ?? []).joined(separator: "; ")
        return AssignmentCopilotFactCard(
            id: "churn",
            title: "Churn risk",
            summary: reasons.isEmpty ? "Churn risk is \(level)." : "Churn risk is \(level): \(reasons).",
            evidenceNodeIDs: [id(node)],
            chart: [],
            hasSupportingFact: true
        )
    }

    private func all(type: String) -> [[String: Any]] {
        nodes.filter { $0["type"] as? String == type }
    }

    private func first(type: String) -> [String: Any]? {
        all(type: type).first
    }

    private func props(_ node: [String: Any]) -> [String: Any] {
        node["properties"] as? [String: Any] ?? [:]
    }

    private func id(_ node: [String: Any]) -> String {
        node["id"] as? String ?? "unknown"
    }
}
