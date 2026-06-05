import Foundation

public enum GraphOperationType: String, Codable, Sendable {
    case addMedicalConstraint = "AddMedicalConstraint"
    case retractMedicalConstraint = "RetractMedicalConstraint"
    case addPreference = "AddPreference"
    case retractPreference = "RetractPreference"
    case addEquipmentAccess = "AddEquipmentAccess"
    case requestClarification = "RequestClarification"
    case archiveStaleObservation = "ArchiveStaleObservation"
}

public enum GraphOperationActor: String, Codable, Sendable {
    case user
    case agent
    case engine
}

public enum GraphOperationScope: String, Codable, Sendable {
    case member
    case session
    case device
}

public struct GraphOperationEffect: Codable, Equatable, Sendable {
    public let subjectID: String?
    public let constraintType: String?
    public let value: String?
    public let sourceText: String?
    public let hard: Bool?
    public let negated: Bool?
    public let status: String?
    public let replacesOperationID: String?
    public let reason: String?
    public let reviewAfter: String?
    public let expiresAt: String?
    public let note: String?
    public let mutationTarget: String?

    enum CodingKeys: String, CodingKey {
        case subjectID = "subject_id"
        case constraintType = "constraint_type"
        case value
        case sourceText = "source_text"
        case hard
        case negated
        case status
        case replacesOperationID = "replaces_operation_id"
        case reason
        case reviewAfter = "review_after"
        case expiresAt = "expires_at"
        case note
        case mutationTarget = "mutation_target"
    }

    public init(subjectID: String? = nil,
                constraintType: String? = nil,
                value: String? = nil,
                sourceText: String? = nil,
                hard: Bool? = nil,
                negated: Bool? = nil,
                status: String? = nil,
                replacesOperationID: String? = nil,
                reason: String? = nil,
                reviewAfter: String? = nil,
                expiresAt: String? = nil,
                note: String? = nil,
                mutationTarget: String? = nil) {
        self.subjectID = subjectID
        self.constraintType = constraintType
        self.value = value
        self.sourceText = sourceText
        self.hard = hard
        self.negated = negated
        self.status = status
        self.replacesOperationID = replacesOperationID
        self.reason = reason
        self.reviewAfter = reviewAfter
        self.expiresAt = expiresAt
        self.note = note
        self.mutationTarget = mutationTarget
    }
}

public struct GraphOperation: Codable, Equatable, Sendable {
    public let operationID: String
    public let operationType: GraphOperationType
    public let actor: GraphOperationActor
    public let createdAt: String
    public let baseArtifactSHA256: String
    public let preconditionRevision: Int
    public let scope: GraphOperationScope
    public let sourceSpanIDs: [String]
    public let effect: GraphOperationEffect

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case operationType = "operation_type"
        case actor
        case createdAt = "created_at"
        case baseArtifactSHA256 = "base_artifact_sha256"
        case preconditionRevision = "precondition_revision"
        case scope
        case sourceSpanIDs = "source_span_ids"
        case effect
    }

    public init(operationID: String,
                operationType: GraphOperationType,
                actor: GraphOperationActor,
                createdAt: String,
                baseArtifactSHA256: String,
                preconditionRevision: Int,
                scope: GraphOperationScope,
                sourceSpanIDs: [String] = [],
                effect: GraphOperationEffect) {
        self.operationID = operationID
        self.operationType = operationType
        self.actor = actor
        self.createdAt = createdAt
        self.baseArtifactSHA256 = baseArtifactSHA256
        self.preconditionRevision = preconditionRevision
        self.scope = scope
        self.sourceSpanIDs = sourceSpanIDs
        self.effect = effect
    }
}

