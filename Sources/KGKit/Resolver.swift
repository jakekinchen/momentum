import Foundation

/// Deterministic local resolver: free text -> typed constraints, never prose
/// decisions. Faithful port of kg/resolver.py (exact/alias + hardcoded canonical
/// cases + "only ..." subset; NO fuzzy/embedding — out of scope in the source).
public enum Resolver {
    private static let boundaryPunctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]{}")

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
                                     graphPaths: [String] = []) throws -> ResolvedConstraint {
        _ = try graph.requireNode(nodeID)
        return ResolvedConstraint(constraintType: constraintType, value: nodeValue(nodeID), hard: hard,
                                  sourceText: sourceText, graphPaths: graphPaths, verified: false,
                                  negated: negated, laterality: laterality,
                                  resolutionStatus: "resolved", safetyBehavior: safetyBehavior)
    }

    private static func unresolved(sourceText: String, normalizedText: String) -> ResolvedConstraint {
        ResolvedConstraint(constraintType: "UnresolvedConcept", value: normalizedText, hard: true,
                           sourceText: sourceText, resolutionStatus: "needs_review",
                           safetyBehavior: "ask_clarification")
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
        for term in terms {
            guard let node = exactLabelOrAliasMatch(term, graph), node.type == "Equipment" else { return nil }
            if seen.contains(node.id) { continue }
            seen.insert(node.id)
            constraints.append(try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                                 nodeID: node.id, hard: true,
                                                 safetyBehavior: "allowed_equipment_only"))
        }
        return constraints
    }

    /// Port of _resolve_single_clause.
    public static func resolveSingleClause(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        let normalized = normalize(text)
        if let eq = try allowedEquipmentSubset(text: text, normalized: normalized, graph: graph) { return eq }

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
}
