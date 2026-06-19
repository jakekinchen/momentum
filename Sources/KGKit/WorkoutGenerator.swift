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
    public let primaryReasonCode: String
    public let primarySeverity: String
    public let graphPaths: [String]
}

public struct AlternativeSummary: Equatable, Sendable {
    public let filteredExerciseID: String
    public let alternativeExerciseID: String
    public let derivedFrom: String
    public let score: Double
    public let scoreComponents: [String: Double]
    public let graphPaths: [String]
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
    public static let quarantinedExerciseIDs: Set<String> = [
        "Exercise:jumping_jack"
    ]

    static let lowerBodyTargets: Set<String> = [
        "MuscleGroup:glutes", "MuscleGroup:quads", "MuscleGroup:hamstrings", "MuscleGroup:calves",
        "MuscleGroup:hip_flexors", "MuscleGroup:hip_adductors", "MuscleGroup:lower_back",
    ]

    static func label(_ g: LocalGraph, _ id: String) -> String { g.nodes[id]?.label ?? id }

    private static func promptMatches(_ normalized: String, _ pattern: String) -> Bool {
        normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedPhrase(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func containsPhrase(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return " \(haystack) ".contains(" \(needle) ")
    }

    private static func exerciseSearchTerms(_ node: GraphNode) -> [String] {
        ([node.label] + node.aliases + [
            node.id,
            String(node.id.split(separator: ":", maxSplits: 1).last ?? "")
                .replacingOccurrences(of: "_", with: " ")
        ])
        .map(normalizedPhrase)
        .filter { !$0.isEmpty }
    }

    private static func exactExerciseCandidateIds(_ prompt: String, _ g: LocalGraph, _ exerciseIDs: [String]) -> [String] {
        let normalizedPrompt = normalizedPhrase(prompt)
        return exerciseIDs.filter { id in
            guard let node = g.nodes[id] else { return false }
            return exerciseSearchTerms(node).contains { containsPhrase(normalizedPrompt, $0) }
        }
    }

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
        let allExerciseIDs = g.nodesByType("Exercise").map { $0.id }
        let exerciseIDs = allExerciseIDs.filter { !quarantinedExerciseIDs.contains($0) }
        let n = prompt.lowercased()
        let exactMatchesIncludingQuarantine = exactExerciseCandidateIds(prompt, g, allExerciseIDs)
        let exactMatches = exactMatchesIncludingQuarantine.filter { !quarantinedExerciseIDs.contains($0) }
        if !exactMatchesIncludingQuarantine.isEmpty {
            return exactMatches
        }
        if n.contains("lower") || n.contains("leg") || n.contains("knee") {
            return exerciseIDs.filter { isLowerBodyCandidate(g, $0) }
        }
        if n.contains("preacher") {
            return exerciseIDs.filter { id in
                label(g, id).lowercased().contains("preacher")
            }
        }
        if promptMatches(n, #"\b(rows?|rowing)\b"#)
            || promptMatches(n, #"\bupper[- ]back\b"#)
            || promptMatches(n, #"\b(lats?|latissimus)\b"#) {
            return exerciseIDs.filter { id in
                g.outgoing(id, predicate: "VARIANT_OF").contains { $0.target == "ExerciseFamily:row_family" }
                    || g.outgoing(id, predicate: "TARGETS").contains {
                        $0.target == "MuscleGroup:upper_back" || $0.target == "MuscleGroup:lats"
                    }
            }
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

    /// Port of generate_workout (exercise-side): resolve(prompt) + memberConstraints -> safety -> alternatives -> sections.
    public static func generateWorkout(engine: SafetyEngine, prompt: String, minutes: Int,
                                       availableEquipment: [String], memberConstraints: [ResolvedConstraint],
                                       memberID: String = "Member:jordan") throws -> WorkoutPlan {
        let g = engine.graph
        let promptConstraints = try Resolver.resolveText(prompt, graph: g)
        let constraints = promptConstraints + memberConstraints
        let candidates = candidateIds(prompt, g)
        let receipts = try engine.evaluateCandidates(candidates, availableEquipment: availableEquipment,
                                                     constraints: constraints)
        let result = try Alternatives.buildWorkoutCandidates(receipts, availableEquipment: availableEquipment, graph: g)
        let sections = workoutSections(g, result.selectedReceipts)
        func summary(_ r: DecisionReceipt) -> ExerciseSummary {
            ExerciseSummary(exerciseID: r.exerciseID, name: label(g, r.exerciseID),
                            decision: r.decision, reasonCodes: r.reasonCodes,
                            primaryReasonCode: r.primaryReasonCode,
                            primarySeverity: r.primarySeverity,
                            graphPaths: r.graphPaths)
        }
        return WorkoutPlan(
            memberID: memberID, prompt: prompt, timeWindowMinutes: minutes,
            availableEquipment: availableEquipment.sorted(),
            resolvedConstraints: constraints,
            unresolvedConcepts: constraints.filter { $0.constraintType == "UnresolvedConcept" },
            warmup: sections.warmup, main: sections.main, cooldown: sections.cooldown,
            selectedExercises: result.selectedReceipts.map(summary),
            filteredExercises: result.filteredReceipts.map(summary),
            alternatives: result.alternatives.map {
                AlternativeSummary(filteredExerciseID: $0.filteredExerciseID,
                                   alternativeExerciseID: $0.alternativeExerciseID,
                                   derivedFrom: $0.derivedFrom,
                                   score: $0.score,
                                   scoreComponents: $0.scoreComponents,
                                   graphPaths: $0.graphPaths)
            })
    }

    /// Runtime bridge: member overlay persistence supplies the active constraints;
    /// the exercise-side generator stays pure and deterministic.
    public static func generateWorkout(view: MergedGraphView, prompt: String, minutes: Int,
                                       availableEquipment: [String],
                                       memberID: String = "Member:jordan") throws -> WorkoutPlan {
        let engine = SafetyEngine(graph: view.graph, rules: view.baseArtifact.safetyRules)
        return try generateWorkout(
            engine: engine,
            prompt: prompt,
            minutes: minutes,
            availableEquipment: availableEquipment,
            memberConstraints: view.activeResolvedConstraints,
            memberID: memberID
        )
    }

    /// Convenience for app startup paths that have a prepared Application
    /// Support KG workspace but have not materialized a view yet.
    public static func generateWorkout(workspace: KGWorkspace, prompt: String, minutes: Int,
                                       availableEquipment: [String],
                                       memberID: String = "Member:jordan") throws -> WorkoutPlan {
        try generateWorkout(
            view: try MergedGraphView(workspace: workspace),
            prompt: prompt,
            minutes: minutes,
            availableEquipment: availableEquipment,
            memberID: memberID
        )
    }
}
