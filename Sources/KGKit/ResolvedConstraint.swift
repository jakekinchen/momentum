/// Mirror of kg/constraints.py ResolvedConstraint. Safety stays graph-driven;
/// this is parsed-input, not a decision.
public struct ResolvedConstraint: Equatable, Sendable {
    public let constraintType: String
    public let value: String
    public let hard: Bool
    public let sourceText: String
    public let graphPaths: [String]
    public let verified: Bool
    public let negated: Bool
    public let laterality: String?
    public let resolutionStatus: String
    public let safetyBehavior: String?
    public let confidence: Double
    public let resolutionMethod: String

    public init(constraintType: String, value: String, hard: Bool, sourceText: String,
                graphPaths: [String] = [], verified: Bool = false,
                negated: Bool = false, laterality: String? = nil,
                resolutionStatus: String = "resolved", safetyBehavior: String? = nil,
                confidence: Double = 1.0, resolutionMethod: String = "exact") {
        self.constraintType = constraintType; self.value = value; self.hard = hard
        self.sourceText = sourceText; self.graphPaths = graphPaths; self.verified = verified
        self.negated = negated; self.laterality = laterality
        self.resolutionStatus = resolutionStatus; self.safetyBehavior = safetyBehavior
        self.confidence = confidence; self.resolutionMethod = resolutionMethod
    }

    /// Node id this constraint refers to (_constraint_node_id in kg/safety.py).
    public var nodeID: String { NodeID.make(constraintType, value) }
}

/// Port of _node_id (kg/safety.py): "Prefix:value" with value lowercased,
/// spaces -> underscores, trimmed; already-prefixed values pass through.
public enum NodeID {
    public static func make(_ prefix: String, _ value: String) -> String {
        if value.hasPrefix("\(prefix):") { return value }
        let normalized = value.trimmingCharacters(in: .whitespaces)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(prefix):\(normalized)"
    }
}
