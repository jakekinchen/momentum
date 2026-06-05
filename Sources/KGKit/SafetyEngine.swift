/// Deterministic safety evaluation over the local graph. Port of kg/safety.py.
/// The graph decides; no LLM, no vector search.
public struct SafetyEngine {
    public let graph: LocalGraph
    public let rules: [SafetyRule]

    public init(graph: LocalGraph, rules: [SafetyRule]) {
        self.graph = graph; self.rules = rules
    }

    // _matches_properties: every expected key must match the edge property.
    private func matches(edge: GraphEdge, rule: SafetyRule) -> Bool {
        guard rule.matchEdgePredicate == edge.predicate else { return false }
        for (key, expectation) in rule.matchProperties {
            if !expectation.matches(edge.properties[key]) { return false }
        }
        return true
    }

    // _stress_hits_restriction: [] if equal, path if a PART_OF path exists, nil otherwise.
    private func stressHitsRestriction(_ stressTarget: String, _ restrictionID: String) throws -> [String]? {
        if stressTarget == restrictionID { return [] }
        let path = try graph.partOfPath(from: stressTarget, to: restrictionID)
        return path.isEmpty ? nil : path
    }

    // _restriction_applies_to_rule: restriction is, or is PART_OF, one of the rule's concepts.
    private func restrictionAppliesToRule(_ restrictionID: String, _ rule: SafetyRule) throws -> Bool {
        for concept in rule.usesConcepts {
            if restrictionID == concept { return true }
            if try !graph.partOfPath(from: restrictionID, to: concept).isEmpty { return true }
        }
        return false
    }

    /// Port of _medical_reasons.
    public func medicalReasons(exerciseID: String, constraints: [ResolvedConstraint]) throws -> [SafetyReason] {
        let activeRestrictions = constraints
            .filter { $0.constraintType == "BodyRegion" && $0.hard && !$0.negated }
            .map { $0.nodeID }
        if activeRestrictions.isEmpty { return [] }

        var reasons: [SafetyReason] = []
        for stressEdge in graph.outgoing(exerciseID, predicate: "STRESSES") {
            for restrictionID in activeRestrictions {
                guard let restrictionPath = try stressHitsRestriction(stressEdge.target, restrictionID) else { continue }
                for rule in rules {
                    guard rule.severity == "MEDICAL_HARD_BLOCK" else { continue }
                    guard try restrictionAppliesToRule(restrictionID, rule) else { continue }
                    guard rule.matchEdgePredicate == "STRESSES" else { continue }
                    guard matches(edge: stressEdge, rule: rule) else { continue }
                    let rulePaths = rule.usesConcepts.map { "\(rule.id) -USES_CONCEPT-> \($0)" }
                    reasons.append(SafetyReason(
                        severity: rule.severity,
                        reasonCode: rule.reasonCode,
                        graphPaths: [stressEdge.path()] + restrictionPath + rulePaths))
                }
            }
        }
        return reasons
    }
}
