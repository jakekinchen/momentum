import Foundation

/// Deterministic local resolver: free text -> typed constraints, never prose
/// decisions. Faithful port of kg/resolver.py (exact/alias + hardcoded canonical
/// cases + "only ..." subset + high-confidence local typo aliases; no embedding.
public enum Resolver {
    private static let boundaryPunctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]{}")
    private static let localFuzzyAliases = [
        "kne": "knee",
        "bad low back": "bad lower back",
        "low back": "bad lower back",
        "lowerback": "bad lower back",
        "barbel": "barbell",
        "no barbel": "no barbell",
        "dumbell": "dumbbell",
        "dumbells": "dumbbell",
        "dbs": "dumbbell",
        "kettle bell": "kettlebell",
        "kettle bells": "kettlebell",
        "kbell": "kettlebell",
        "loop band": "resistance band - loop",
        "resistance band loop": "resistance band - loop",
        "dead lift": "exclude deadlifts",
        "dead lifts": "exclude deadlifts",
        "exclude dead lifts": "exclude deadlifts",
        "pec": "pecs",
        "pectorals": "pecs",
        "chest intent": "pecs",
    ]

    /// Port of _normalize: trim, lowercase, collapse internal whitespace, strip boundary punctuation.
    public static func normalize(_ text: String) -> String {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: boundaryPunctuation)
    }

    private static func nodeValue(_ nodeID: String) -> String {
        String(nodeID.split(separator: ":", maxSplits: 1).last ?? "")
    }

    /// Port of _exact_label_or_alias_match: sorted by node id; match normalized label/aliases.
    static func exactLabelOrAliasMatch(_ normalized: String, _ graph: LocalGraph) -> GraphNode? {
        for node in graph.nodes.values.sorted(by: { $0.id < $1.id }) {
            var terms: Set<String> = [normalize(node.label)]
            for alias in node.aliases { terms.insert(normalize(alias)) }
            if terms.contains(normalized) { return node }
        }
        return nil
    }

    private static func resolvedNode(graph: LocalGraph, sourceText: String, constraintType: String,
                                     nodeID: String, hard: Bool = false, negated: Bool = false,
                                     laterality: String? = nil, safetyBehavior: String? = nil,
                                     graphPaths: [String] = [],
                                     confidence: Double = 1.0,
                                     resolutionMethod: String = "exact") throws -> ResolvedConstraint {
        _ = try graph.requireNode(nodeID)
        return ResolvedConstraint(constraintType: constraintType, value: nodeValue(nodeID), hard: hard,
                                  sourceText: sourceText, graphPaths: graphPaths, verified: false,
                                  negated: negated, laterality: laterality,
                                  resolutionStatus: "resolved", safetyBehavior: safetyBehavior,
                                  confidence: confidence, resolutionMethod: resolutionMethod)
    }

    private static func unresolved(sourceText: String, normalizedText: String) -> ResolvedConstraint {
        ResolvedConstraint(constraintType: "UnresolvedConcept", value: normalizedText, hard: true,
                           sourceText: sourceText, resolutionStatus: "needs_review",
                           safetyBehavior: "ask_clarification",
                           confidence: 0.0, resolutionMethod: "unresolved")
    }

    private static func withResolutionMetadata(_ constraints: [ResolvedConstraint],
                                               sourceText: String,
                                               confidence: Double,
                                               resolutionMethod: String) -> [ResolvedConstraint] {
        constraints.map { constraint in
            ResolvedConstraint(
                constraintType: constraint.constraintType,
                value: constraint.value,
                hard: constraint.hard,
                sourceText: sourceText,
                graphPaths: constraint.graphPaths,
                verified: constraint.verified,
                negated: constraint.negated,
                laterality: constraint.laterality,
                resolutionStatus: constraint.resolutionStatus,
                safetyBehavior: constraint.safetyBehavior,
                confidence: confidence,
                resolutionMethod: resolutionMethod
            )
        }
    }

    private static func splitEquipmentTerms(_ s: String) -> [String] {
        // Port of re.split(r"\s*(?:,| and )\s*", ...): split on comma or " and ".
        let sentinel = "\u{1}"
        let replaced = s.replacingOccurrences(of: "\\s*(?:,| and )\\s*", with: sentinel, options: .regularExpression)
        return replaced.split(separator: Character(sentinel), omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Port of _allowed_equipment_subset: "only X, Y and Z" -> hard Equipment constraints; nil if any non-equipment.
    private static func allowedEquipmentSubset(text: String, normalized: String,
                                               graph: LocalGraph) throws -> [ResolvedConstraint]? {
        guard normalized.hasPrefix("only ") else { return nil }
        let equipmentText = String(normalized.dropFirst("only ".count)).trimmingCharacters(in: .whitespaces)
        let terms = splitEquipmentTerms(equipmentText)
        if terms.isEmpty { return nil }
        var constraints: [ResolvedConstraint] = []
        var seen: Set<String> = []
        var usedLocalAlias = false
        for term in terms {
            let lookupTerm: String
            if let canonical = localFuzzyAliases[term] {
                lookupTerm = normalize(canonical)
                usedLocalAlias = true
            } else {
                lookupTerm = term
            }
            guard let node = exactLabelOrAliasMatch(lookupTerm, graph), node.type == "Equipment" else { return nil }
            if seen.contains(node.id) { continue }
            seen.insert(node.id)
            constraints.append(try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                                 nodeID: node.id, hard: true,
                                                 safetyBehavior: "allowed_equipment_only"))
        }
        if usedLocalAlias {
            return withResolutionMetadata(
                constraints,
                sourceText: text,
                confidence: 0.92,
                resolutionMethod: "local_fuzzy_alias"
            )
        }
        return constraints
    }

    /// Port of _resolve_single_clause.
    public static func resolveSingleClause(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        let normalized = normalize(text)
        if let eq = try allowedEquipmentSubset(text: text, normalized: normalized, graph: graph) { return eq }

        if let canonical = localFuzzyAliases[normalized] {
            let constraints = try resolveSingleClause(canonical, graph: graph)
            if !(constraints.count == 1 && constraints[0].constraintType == "UnresolvedConcept") {
                return withResolutionMetadata(
                    constraints,
                    sourceText: text,
                    confidence: 0.92,
                    resolutionMethod: "local_fuzzy_alias"
                )
            }
        }

        switch normalized {
        case "knee":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:knee",
                                     graphPaths: try graph.partOfClosurePaths("BodyRegion:knee"))]
        case "left knee":
            let paths = graph.outgoing("BodyRegion:left_knee", predicate: "PART_OF").map { $0.path() }
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:left_knee", laterality: "left", graphPaths: paths)]
        case "bad lower back":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:lower_back", hard: true,
                                     safetyBehavior: "block_if_safety_critical",
                                     graphPaths: try graph.partOfClosurePaths("BodyRegion:lower_back"))]
        case "kettlebell":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                     nodeID: "Equipment:kettlebell")]
        case "no barbell":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                     nodeID: "Equipment:barbell", hard: true, negated: true)]
        case "exclude deadlifts":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "ExerciseFamily",
                                     nodeID: "ExerciseFamily:deadlift_family", hard: true, negated: true)]
        default:
            if let node = exactLabelOrAliasMatch(normalized, graph) {
                return [try resolvedNode(graph: graph, sourceText: text, constraintType: node.type, nodeID: node.id)]
            }
            return [unresolved(sourceText: text, normalizedText: normalized)]
        }
    }

    private static let requestVerbs = ["build ", "create ", "make ", "plan ", "program "]
    private static let requestNouns = ["session", "workout", "routine", "plan"]

    /// Port of _prompt_clauses: split on . ; ! ? keeping the delimiter; keep clauses that normalize non-empty.
    private static func promptClauses(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "[^.;!?]+[.;!?]*")
        let ns = text as NSString
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let clause = ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalize(clause).isEmpty { out.append(clause) }
        }
        return out
    }

    private static func isRequestShapeClause(_ normalized: String) -> Bool {
        requestVerbs.contains { normalized.hasPrefix($0) } && requestNouns.contains { normalized.contains($0) }
    }

    /// Port of _resolve_prompt_clauses.
    private static func resolvePromptClauses(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint]? {
        let clauses = promptClauses(text)
        if clauses.count <= 1 { return nil }
        var resolved: [ResolvedConstraint] = []
        var unresolved: [ResolvedConstraint] = []
        for clause in clauses {
            if isRequestShapeClause(normalize(clause)) { continue }
            let cs = try resolveSingleClause(clause, graph: graph)
            if cs.count == 1 && cs[0].constraintType == "UnresolvedConcept" {
                unresolved.append(contentsOf: cs)
            } else {
                resolved.append(contentsOf: cs)
            }
        }
        if !resolved.isEmpty { return resolved + unresolved }
        if !unresolved.isEmpty { return unresolved }
        return nil
    }

    /// Port of resolve_text: single-clause first; fall back to multi-clause only if the single result is one UnresolvedConcept.
    public static func resolveText(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        let single = try resolveSingleClause(text, graph: graph)
        if !(single.count == 1 && single[0].constraintType == "UnresolvedConcept") { return single }
        if let prompt = try resolvePromptClauses(text, graph: graph) { return prompt }
        return single
    }
}
