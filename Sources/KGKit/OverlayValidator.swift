import Foundation

public struct OverlayValidator: Sendable {
    public let baseArtifactSHA256: String

    public enum ValidationError: Error, Equatable {
        case baseArtifactMismatch(expected: String, actual: String)
        case revisionMismatch(expected: Int, actual: Int)
        case canonicalMutationForbidden(String)
        case missingRequiredField(String)
        case unsupportedConstraintType(String)
    }

    public init(baseArtifactSHA256: String) {
        self.baseArtifactSHA256 = baseArtifactSHA256
    }

    public func validate(_ operation: GraphOperation, currentRevision: Int) throws {
        guard operation.baseArtifactSHA256 == baseArtifactSHA256 else {
            throw ValidationError.baseArtifactMismatch(
                expected: baseArtifactSHA256,
                actual: operation.baseArtifactSHA256
            )
        }
        guard operation.preconditionRevision == currentRevision else {
            throw ValidationError.revisionMismatch(
                expected: currentRevision,
                actual: operation.preconditionRevision
            )
        }
        if let mutationTarget = operation.effect.mutationTarget,
           referencesCanonicalGraphMutation(mutationTarget) {
            throw ValidationError.canonicalMutationForbidden(mutationTarget)
        }

        switch operation.operationType {
        case .addMedicalConstraint:
            try require(operation.effect.constraintType, "effect.constraint_type")
            try require(operation.effect.value, "effect.value")
            guard operation.effect.constraintType == "BodyRegion" else {
                throw ValidationError.unsupportedConstraintType(operation.effect.constraintType ?? "")
            }
        case .retractMedicalConstraint:
            try require(operation.effect.replacesOperationID, "effect.replaces_operation_id")
            try require(operation.effect.reason, "effect.reason")
        case .addPreference, .retractPreference, .addEquipmentAccess,
             .requestClarification, .archiveStaleObservation:
            try require(operation.effect.value ?? operation.effect.subjectID ?? operation.effect.note,
                        "effect.value|subject_id|note")
        }
    }

    private func require(_ value: String?, _ field: String) throws {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingRequiredField(field)
        }
    }

    private func referencesCanonicalGraphMutation(_ target: String) -> Bool {
        let forbiddenTokens = [
            "PART_OF", "STRESSES", "REQUIRES", "VARIANT_OF", "MAPS_TO", "USES_CONCEPT",
            "Exercise:", "BodyRegion:", "SafetyRule:"
        ]
        return forbiddenTokens.contains { target.contains($0) }
    }
}

