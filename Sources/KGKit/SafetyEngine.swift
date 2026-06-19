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
        if !path.isEmpty { return path }
        let reversePath = try graph.partOfPath(from: restrictionID, to: stressTarget)
        return reversePath.isEmpty ? nil : reversePath
    }

    // _restriction_applies_to_rule: restriction is, or is PART_OF, one of the rule's concepts.
    private func restrictionAppliesToRule(_ restrictionID: String, _ rule: SafetyRule) throws -> Bool {
        for concept in rule.usesConcepts {
            if restrictionID == concept { return true }
            if try !graph.partOfPath(from: restrictionID, to: concept).isEmpty { return true }
        }
        return false
    }

    /// Port of _equipment_ids: normalize available equipment labels to node ids.
    public func equipmentIDs(_ available: [String]) -> Set<String> {
        Set(available.map { NodeID.make("Equipment", $0) })
    }

    /// Port of _equipment_reasons.
    public func equipmentReasons(exerciseID: String, availableEquipment: [String],
                                 constraints: [ResolvedConstraint]) -> [SafetyReason] {
        let available = equipmentIDs(availableEquipment)
        let disallowed = Set(constraints
            .filter { $0.constraintType == "Equipment" && $0.hard && $0.negated }
            .map { $0.nodeID })

        var reasons: [SafetyReason] = []
        for edge in graph.outgoing(exerciseID, predicate: "REQUIRES") {
            let value = edge.target.split(separator: ":", maxSplits: 1).last.map(String.init) ?? edge.target
            if !available.contains(edge.target) {
                reasons.append(SafetyReason(severity: "EQUIPMENT_HARD_BLOCK",
                    reasonCode: "MISSING_EQUIPMENT:\(value)", graphPaths: [edge.path()]))
            }
            if disallowed.contains(edge.target) {
                reasons.append(SafetyReason(severity: "EQUIPMENT_HARD_BLOCK",
                    reasonCode: "DISALLOWED_EQUIPMENT:\(value)", graphPaths: [edge.path()]))
            }
        }
        return reasons
    }

    /// Port of _prompt_exclusion_reasons.
    public func promptExclusionReasons(exerciseID: String, constraints: [ResolvedConstraint]) -> [SafetyReason] {
        let excluded = Set(constraints
            .filter { $0.constraintType == "ExerciseFamily" && $0.hard && $0.negated }
            .map { $0.nodeID })
        if excluded.isEmpty { return [] }

        var reasons: [SafetyReason] = []
        for edge in graph.outgoing(exerciseID, predicate: "VARIANT_OF") where excluded.contains(edge.target) {
            let value = edge.target.split(separator: ":", maxSplits: 1).last.map(String.init) ?? edge.target
            reasons.append(SafetyReason(severity: "PROMPT_EXCLUSION",
                reasonCode: "PROMPT_EXCLUDED_FAMILY:\(value)", graphPaths: [edge.path()]))
        }
        return reasons
    }

    /// Port of _receipt.
    private func receipt(exerciseID: String, reasons: [SafetyReason],
                         availableEquipment: Set<String>, constraints: [ResolvedConstraint]) -> DecisionReceipt {
        let decision: String, severity: String, reasonCodes: [String], primaryReason: String, graphPaths: [String]
        if !reasons.isEmpty {
            severity = Severity.primary(reasons.map { $0.severity }) ?? "SOFT_PENALTY"
            primaryReason = reasons.first { $0.severity == severity }!.reasonCode
            decision = Severity.isHardBlock(severity) ? "filtered" : "downranked"
            reasonCodes = reasons.map { $0.reasonCode }
            graphPaths = reasons.flatMap { $0.graphPaths }
        } else {
            severity = "BOOST"; decision = "selected"
            reasonCodes = ["PASSED_SAFETY"]; primaryReason = "PASSED_SAFETY"; graphPaths = []
        }
        let fingerprint = CanonicalJSON.fingerprint(
            availableEquipment: Array(availableEquipment), constraints: constraints, exerciseID: exerciseID)
        return DecisionReceipt(
            exerciseID: exerciseID, decision: decision, primarySeverity: severity,
            reasonCodes: reasonCodes, primaryReasonCode: primaryReason, graphPaths: graphPaths,
            constraintFingerprint: fingerprint, graphVersion: graph.graphVersion,
            rulesetVersion: graph.rulesetVersion, ontologyLockVersion: graph.ontologyLockVersion)
    }

    /// Port of evaluate_candidates. When candidateIDs is nil, evaluate all Exercise nodes sorted by id.
    public func evaluateCandidates(_ candidateIDs: [String]? = nil, availableEquipment: [String],
                                   constraints: [ResolvedConstraint]) throws -> [DecisionReceipt] {
        let available = equipmentIDs(availableEquipment)
        let exercises = candidateIDs ?? graph.nodesByType("Exercise").map { $0.id }
        var receipts: [DecisionReceipt] = []
        for exerciseID in exercises {
            try graph.requireNode(exerciseID)
            let reasons = try medicalReasons(exerciseID: exerciseID, constraints: constraints)
                + equipmentReasons(exerciseID: exerciseID, availableEquipment: availableEquipment, constraints: constraints)
                + promptExclusionReasons(exerciseID: exerciseID, constraints: constraints)
            receipts.append(receipt(exerciseID: exerciseID, reasons: reasons,
                                    availableEquipment: available, constraints: constraints))
        }
        return receipts
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
