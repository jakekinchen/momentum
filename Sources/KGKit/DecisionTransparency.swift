import Foundation

public enum ExclusionRecoveryPolicy: String, Codable, Equatable, Sendable {
    case notExcluded = "not_excluded"
    case stateCorrectionRequired = "state_correction_required"
    case sessionOverrideAllowed = "session_override_allowed"
    case clarificationRequired = "clarification_required"
    case notOverrideable = "not_overrideable"
}

public struct DecisionExplanation: Codable, Equatable, Sendable {
    public let exerciseID: String
    public let decision: String
    public let primaryReasonCode: String
    public let primarySeverity: String
    public let recoveryPolicy: ExclusionRecoveryPolicy
    public let canUseImmediately: Bool
    public let correctionOperationType: GraphOperationType?
    public let summary: String
    public let graphPaths: [String]

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case decision
        case primaryReasonCode = "primary_reason_code"
        case primarySeverity = "primary_severity"
        case recoveryPolicy = "recovery_policy"
        case canUseImmediately = "can_use_immediately"
        case correctionOperationType = "correction_operation_type"
        case summary
        case graphPaths = "graph_paths"
    }
}

public enum DecisionTransparency {
    public static func explain(receipt: DecisionReceipt,
                               overlay: MemberOverlayState) -> DecisionExplanation {
        if receipt.decision == "selected" {
            return DecisionExplanation(
                exerciseID: receipt.exerciseID,
                decision: receipt.decision,
                primaryReasonCode: receipt.primaryReasonCode,
                primarySeverity: receipt.primarySeverity,
                recoveryPolicy: .notExcluded,
                canUseImmediately: true,
                correctionOperationType: nil,
                summary: "Selected under the current base graph and member overlay.",
                graphPaths: receipt.graphPaths
            )
        }

        let policy: ExclusionRecoveryPolicy
        let canUseImmediately: Bool
        let operation: GraphOperationType?
        let summary: String

        if receipt.primarySeverity == "MEDICAL_HARD_BLOCK" {
            policy = .stateCorrectionRequired
            canUseImmediately = false
            operation = .retractMedicalConstraint
            let source = overlay.activeConstraints.first?.sourceText ?? "an active health constraint"
            summary = "Excluded because \(source) is active. The user can correct that stored fact if it is no longer true, then rerun safety."
        } else if receipt.primarySeverity == "EQUIPMENT_HARD_BLOCK" {
            policy = .stateCorrectionRequired
            canUseImmediately = false
            operation = .addEquipmentAccess
            summary = "Excluded because the current equipment state does not support this exercise. The user can update equipment access, then rerun safety."
        } else if receipt.primarySeverity == "PROMPT_EXCLUSION" {
            policy = .sessionOverrideAllowed
            canUseImmediately = false
            operation = .addPreference
            summary = "Excluded because of the current prompt or preference. The user can allow it for this session, then rerun safety."
        } else if receipt.primarySeverity == "UNRESOLVED_CONCEPT" {
            policy = .clarificationRequired
            canUseImmediately = false
            operation = .requestClarification
            summary = "Excluded because the graph needs clarification before it can decide safely."
        } else {
            policy = .notOverrideable
            canUseImmediately = false
            operation = nil
            summary = "Excluded by a non-overrideable graph decision."
        }

        return DecisionExplanation(
            exerciseID: receipt.exerciseID,
            decision: receipt.decision,
            primaryReasonCode: receipt.primaryReasonCode,
            primarySeverity: receipt.primarySeverity,
            recoveryPolicy: policy,
            canUseImmediately: canUseImmediately,
            correctionOperationType: operation,
            summary: summary,
            graphPaths: receipt.graphPaths
        )
    }
}
