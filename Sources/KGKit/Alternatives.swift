import Foundation

/// One deterministic alternative for a filtered exercise (kg/alternatives.py AlternativeRecord).
public struct AlternativeRecord: Equatable, Sendable {
    public let filteredExerciseID: String
    public let alternativeExerciseID: String
    public let derivedFrom: String
    public let score: Double
    public let scoreComponents: [String: Double]
    public let graphPaths: [String]
}

/// Small workout-candidate contract (kg/alternatives.py WorkoutCandidateResult).
public struct WorkoutCandidateResult: Equatable, Sendable {
    public let selectedReceipts: [DecisionReceipt]
    public let filteredReceipts: [DecisionReceipt]
    public let alternatives: [AlternativeRecord]
}

/// Port of kg/alternatives.py. Alternatives come only from the already-safe (selected) pool.
public enum Alternatives {
    /// Python round(x, 6), round-half-to-even.
    public static func roundTo6(_ x: Double) -> Double {
        (x * 1_000_000).rounded(.toNearestOrEven) / 1_000_000
    }

    private static func targets(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "TARGETS").map { $0.target })
    }
    private static func patterns(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "HAS_PATTERN").map { $0.target })
    }
    private static func requires(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "REQUIRES").map { $0.target })
    }
    private static func priorityScore(_ g: LocalGraph, _ id: String) -> Double {
        if let node = g.nodes[id], case let .double(v)? = node.properties["priority_score"] { return v }
        return 0.0
    }

    private static func targetOverlap(_ g: LocalGraph, _ filtered: String, _ alt: String) -> Double {
        let a = targets(g, filtered), b = targets(g, alt)
        if a.isEmpty || b.isEmpty { return 0.0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
    private static func patternSimilarity(_ g: LocalGraph, _ filtered: String, _ alt: String) -> Double {
        let a = patterns(g, filtered), b = patterns(g, alt)
        if a.isEmpty || b.isEmpty { return 0.0 }
        return a.isDisjoint(with: b) ? 0.0 : 1.0
    }
    private static func equipmentPreference(_ g: LocalGraph, _ alt: String, _ available: Set<String>) -> Double {
        let req = requires(g, alt)
        if req.isEmpty { return 1.0 }
        return req.isSubset(of: available) ? 1.0 : 0.0
    }

    static func scoreComponents(_ g: LocalGraph, _ filtered: String, _ alt: String,
                                _ available: Set<String>) -> [String: Double] {
        [
            "target_overlap": targetOverlap(g, filtered, alt),
            "movement_pattern_similarity": patternSimilarity(g, filtered, alt),
            "equipment_preference": equipmentPreference(g, alt, available),
            "priority_tier": priorityScore(g, alt),
        ]
    }

    /// Port of _weighted_score.
    public static func weightedScore(_ c: [String: Double]) -> Double {
        roundTo6(
            0.45 * (c["target_overlap"] ?? 0)
          + 0.35 * (c["movement_pattern_similarity"] ?? 0)
          + 0.10 * (c["equipment_preference"] ?? 0)
          + 0.10 * (c["priority_tier"] ?? 0)
        )
    }

    /// Port of _equipment_ids (same normalization as the safety engine).
    static func equipmentIDs(_ available: [String]) -> Set<String> {
        Set(available.map { NodeID.make("Equipment", $0) })
    }
}
