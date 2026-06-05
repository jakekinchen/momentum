import Foundation

public struct Prescription: Equatable, Sendable {
    public let exerciseID: String
    public let name: String
    public let sets: Int?
    public let reps: String?
    public let restSeconds: Int?
    public let durationSeconds: Int?
}

public struct ExerciseSummary: Equatable, Sendable {
    public let exerciseID: String
    public let name: String
    public let decision: String
    public let reasonCodes: [String]
}

public struct AlternativeSummary: Equatable, Sendable {
    public let filteredExerciseID: String
    public let alternativeExerciseID: String
    public let score: Double
}

public struct WorkoutPlan: Equatable, Sendable {
    public let memberID: String
    public let prompt: String
    public let timeWindowMinutes: Int
    public let availableEquipment: [String]
    public let resolvedConstraints: [ResolvedConstraint]
    public let unresolvedConcepts: [ResolvedConstraint]
    public let warmup: [Prescription]
    public let main: [Prescription]
    public let cooldown: [Prescription]
    public let selectedExercises: [ExerciseSummary]
    public let filteredExercises: [ExerciseSummary]
    public let alternatives: [AlternativeSummary]
}

/// Exercise-side workout generator (kg/workout_generator.py generate_workout).
/// Member-graph derivation is intentionally external (caller passes availableEquipment + memberConstraints).
public enum WorkoutGenerator {
    static let lowerBodyTargets: Set<String> = [
        "MuscleGroup:glutes", "MuscleGroup:quads", "MuscleGroup:hamstrings", "MuscleGroup:calves",
        "MuscleGroup:hip_flexors", "MuscleGroup:hip_adductors", "MuscleGroup:lower_back",
    ]

    static func label(_ g: LocalGraph, _ id: String) -> String { g.nodes[id]?.label ?? id }

    public static func priorityScore(_ g: LocalGraph, _ id: String) -> Double {
        if let n = g.nodes[id], case let .double(v)? = n.properties["priority_score"] { return v }
        return 0.0
    }
    private static func boolProp(_ g: LocalGraph, _ id: String, _ key: String) -> Bool {
        if let n = g.nodes[id], case let .bool(v)? = n.properties[key] { return v }
        return false
    }

    public static func isLowerBodyCandidate(_ g: LocalGraph, _ id: String) -> Bool {
        let targets = Set(g.outgoing(id, predicate: "TARGETS").map { $0.target })
        let patterns = g.outgoing(id, predicate: "HAS_PATTERN").map { label(g, $0.target).lowercased() }
        return !targets.isDisjoint(with: lowerBodyTargets) || patterns.contains { $0.contains("lower") }
    }

    public static func candidateIds(_ prompt: String, _ g: LocalGraph) -> [String] {
        let exerciseIDs = g.nodesByType("Exercise").map { $0.id }
        let n = prompt.lowercased()
        if n.contains("lower") || n.contains("leg") || n.contains("knee") {
            return exerciseIDs.filter { isLowerBodyCandidate(g, $0) }
        }
        if n.contains("pec") || n.contains("chest") {
            return exerciseIDs.filter { id in
                g.outgoing(id, predicate: "TARGETS").contains { $0.target == "MuscleGroup:chest" }
            }
        }
        return exerciseIDs
    }

    public static func prescription(_ g: LocalGraph, _ id: String, _ section: String) -> Prescription {
        let name = label(g, id)
        if boolProp(g, id, "is_duration") && !boolProp(g, id, "is_reps") {
            return Prescription(exerciseID: id, name: name, sets: nil, reps: nil,
                                restSeconds: 30, durationSeconds: section == "warmup" ? 40 : 60)
        }
        let warmCool = (section == "warmup" || section == "cooldown")
        return Prescription(exerciseID: id, name: name,
                            sets: warmCool ? 2 : 3,
                            reps: boolProp(g, id, "supports_weight") ? "8-10" : "10-12",
                            restSeconds: warmCool ? 45 : 75, durationSeconds: nil)
    }

    public static func workoutSections(_ g: LocalGraph, _ selected: [DecisionReceipt])
        -> (warmup: [Prescription], main: [Prescription], cooldown: [Prescription]) {
        let selectedIDs = selected.map { $0.exerciseID }
        func isMobility(_ id: String) -> Bool {
            g.outgoing(id, predicate: "HAS_PATTERN").contains { e in
                let l = label(g, e.target).lowercased()
                return l.contains("mobility") || l.contains("regen") || l.contains("yoga")
            }
        }
        let mobility = selectedIDs.filter(isMobility)
        let mobilitySet = Set(mobility)
        var mainIDs = selectedIDs.filter { !mobilitySet.contains($0) }
        mainIDs.sort { a, b in
            let pa = priorityScore(g, a), pb = priorityScore(g, b)
            if pa != pb { return pa > pb }
            return a < b
        }
        let warmupIDs = Array(mobility.prefix(2))
        let mainPick = Array((mainIDs.isEmpty ? selectedIDs : mainIDs).prefix(5))
        let cooldownIDs = Array(mobility.dropFirst(2).prefix(2))
        return (warmupIDs.map { prescription(g, $0, "warmup") },
                mainPick.map { prescription(g, $0, "main") },
                cooldownIDs.map { prescription(g, $0, "cooldown") })
    }
}
