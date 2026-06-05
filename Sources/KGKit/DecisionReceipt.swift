/// Port of SEVERITY_LATTICE / HARD_BLOCK_SEVERITIES / primary_severity (kg/safety.py).
public enum Severity {
    public static let lattice = [
        "MEDICAL_HARD_BLOCK", "EQUIPMENT_HARD_BLOCK", "PROMPT_EXCLUSION",
        "MEMBER_STRONG_DISLIKE", "SOFT_PENALTY", "BOOST",
    ]
    public static let hardBlocks: Set<String> = [
        "MEDICAL_HARD_BLOCK", "EQUIPMENT_HARD_BLOCK", "PROMPT_EXCLUSION",
    ]
    public static func primary(_ reasons: [String]) -> String? {
        lattice.first { reasons.contains($0) }
    }
    public static func isHardBlock(_ severity: String) -> Bool { hardBlocks.contains(severity) }
}

/// Port of DecisionReceipt (kg/safety.py) — the 10 PROV_RECEIPT_REQUIRED_FIELDS.
public struct DecisionReceipt: Equatable, Sendable {
    public let exerciseID: String
    public let decision: String                // selected | filtered | downranked
    public let primarySeverity: String
    public let reasonCodes: [String]
    public let primaryReasonCode: String
    public let graphPaths: [String]
    public let constraintFingerprint: String
    public let graphVersion: String
    public let rulesetVersion: String
    public let ontologyLockVersion: String
}

/// One applicable reason before primary selection (kg/safety.py SafetyReason).
public struct SafetyReason: Equatable, Sendable {
    public let severity: String
    public let reasonCode: String
    public let graphPaths: [String]
}
