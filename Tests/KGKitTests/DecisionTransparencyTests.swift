import XCTest
@testable import KGKit

final class DecisionTransparencyTests: XCTestCase {
    func testMedicalHardBlockIsCorrectableStateButNotImmediateOverride() throws {
        let operation = GraphOperation(
            operationID: "op-knee-pain",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-05T15:00:00Z",
            baseArtifactSHA256: "sha",
            preconditionRevision: 0,
            scope: .member,
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "knee",
                sourceText: "knee pain",
                hard: true,
                negated: false
            )
        )
        let overlay = MemberOverlayState(operations: [operation])
        let receipt = DecisionReceipt(
            exerciseID: "Exercise:goblet_squat",
            decision: "filtered",
            primarySeverity: "MEDICAL_HARD_BLOCK",
            reasonCodes: ["ACTIVE_KNEE_RESTRICTION"],
            primaryReasonCode: "ACTIVE_KNEE_RESTRICTION",
            graphPaths: [
                "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee",
                "BodyRegion:left_knee -PART_OF-> BodyRegion:knee",
            ],
            constraintFingerprint: "fingerprint",
            graphVersion: "graph",
            rulesetVersion: "rules",
            ontologyLockVersion: "ontology"
        )

        let explanation = DecisionTransparency.explain(receipt: receipt, overlay: overlay)
        XCTAssertEqual(explanation.recoveryPolicy, .stateCorrectionRequired)
        XCTAssertFalse(explanation.canUseImmediately)
        XCTAssertEqual(explanation.correctionOperationType, .retractMedicalConstraint)
        XCTAssertTrue(explanation.summary.contains("knee pain"))
        XCTAssertEqual(explanation.graphPaths.count, 2)
    }

    func testPromptExclusionCanBeOfferedAsSessionOverrideOnlyAfterSafetyRerun() {
        let receipt = DecisionReceipt(
            exerciseID: "Exercise:kb_deadlift",
            decision: "filtered",
            primarySeverity: "PROMPT_EXCLUSION",
            reasonCodes: ["PROMPT_EXCLUDED_FAMILY:deadlift_family"],
            primaryReasonCode: "PROMPT_EXCLUDED_FAMILY:deadlift_family",
            graphPaths: ["Exercise:kb_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family"],
            constraintFingerprint: "fingerprint",
            graphVersion: "graph",
            rulesetVersion: "rules",
            ontologyLockVersion: "ontology"
        )

        let explanation = DecisionTransparency.explain(
            receipt: receipt,
            overlay: MemberOverlayState(operations: [])
        )
        XCTAssertEqual(explanation.recoveryPolicy, .sessionOverrideAllowed)
        XCTAssertFalse(explanation.canUseImmediately)
        XCTAssertEqual(explanation.correctionOperationType, .addPreference)
    }

    func testSelectedReceiptHasNoCorrectionPath() {
        let receipt = DecisionReceipt(
            exerciseID: "Exercise:glute_bridge",
            decision: "selected",
            primarySeverity: "BOOST",
            reasonCodes: ["PASSED_SAFETY"],
            primaryReasonCode: "PASSED_SAFETY",
            graphPaths: [],
            constraintFingerprint: "fingerprint",
            graphVersion: "graph",
            rulesetVersion: "rules",
            ontologyLockVersion: "ontology"
        )

        let explanation = DecisionTransparency.explain(
            receipt: receipt,
            overlay: MemberOverlayState(operations: [])
        )
        XCTAssertEqual(explanation.recoveryPolicy, .notExcluded)
        XCTAssertTrue(explanation.canUseImmediately)
        XCTAssertNil(explanation.correctionOperationType)
    }

    func testDecisionExplanationEncodesContractSnakeCase() throws {
        let explanation = DecisionExplanation(
            exerciseID: "Exercise:goblet_squat",
            decision: "filtered",
            primaryReasonCode: "ACTIVE_KNEE_RESTRICTION",
            primarySeverity: "MEDICAL_HARD_BLOCK",
            recoveryPolicy: .stateCorrectionRequired,
            canUseImmediately: false,
            correctionOperationType: .retractMedicalConstraint,
            summary: "Excluded because knee pain is active.",
            graphPaths: ["Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(explanation), as: UTF8.self)
        XCTAssertTrue(json.contains("\"exercise_id\":\"Exercise:goblet_squat\""))
        XCTAssertTrue(json.contains("\"recovery_policy\":\"state_correction_required\""))
        XCTAssertTrue(json.contains("\"correction_operation_type\":\"RetractMedicalConstraint\""))
        XCTAssertFalse(json.contains("exerciseID"))
    }
}
