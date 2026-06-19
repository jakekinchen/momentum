import XCTest
@testable import KGKit

final class AssignmentArtifactTests: XCTestCase {
    func testAssessmentArtifactLoadsAllGoldenExercisesAndRecordsSource() throws {
        let data = try ArtifactLoader.assessmentBundledData()
        let artifact = try GraphArtifact.decode(from: data)
        let graph = try LocalGraph(artifact: artifact)

        XCTAssertEqual(graph.nodesByType("Exercise").count, 50)
        XCTAssertEqual(artifact.graphVersion, "assessment-fixture-generated-v0")
        XCTAssertEqual(artifact.rulesetVersion, KGVersion.rulesetVersion)
        XCTAssertEqual(artifact.ontologyLockVersion, KGVersion.ontologyLockVersion)
        XCTAssertEqual(artifact.safetyRules.count, 3)

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(raw["artifact_kind"] as? String, "assignment_assessment_runtime")
        XCTAssertEqual(
            raw["source_snapshot_commit"] as? String,
            "4b8c67246a659c26bd222079c5c7829d295acad9"
        )
        let hashes = try XCTUnwrap(raw["source_hashes"] as? [String: String])
        XCTAssertEqual(hashes["exercises_sha256"], "ffdcf6b3b51787d1f14b327ee9d31b9b1f8ee469eaa11068180f056ce5118798")
        XCTAssertEqual(hashes["member_context_sha256"], "c2e6373eaeb10c889d06e46b5ceb7a5f5a5df463d68198dc615d2ee9099675d2")
    }

    func testAssessmentArtifactEvaluatesEveryGoldenExerciseWithArtifactProvenance() throws {
        let artifact = try ArtifactLoader.assessmentBundled()
        let graph = try LocalGraph(artifact: artifact)
        let engine = SafetyEngine(graph: graph, rules: artifact.safetyRules)
        let receipts = try engine.evaluateCandidates(
            availableEquipment: ["Dumbbell", "Kettlebell", "Yoga Mat"],
            constraints: [
                ResolvedConstraint(
                    constraintType: "BodyRegion",
                    value: "left_knee",
                    hard: true,
                    sourceText: "Jordan active left knee recovery"
                )
            ]
        )

        XCTAssertEqual(receipts.count, 50)
        XCTAssertTrue(receipts.contains { $0.decision == "selected" })
        XCTAssertTrue(receipts.contains { $0.decision == "filtered" })
        XCTAssertTrue(receipts.allSatisfy { $0.graphVersion == "assessment-fixture-generated-v0" })
    }

    func testLeftKneeRestrictionHitsGenericKneeStressInAssessmentGraph() throws {
        let artifact = try ArtifactLoader.assessmentBundled()
        let graph = try LocalGraph(artifact: artifact)
        let engine = SafetyEngine(graph: graph, rules: artifact.safetyRules)
        let receipts = try engine.evaluateCandidates(
            ["Exercise:kettlebell_goblet_cyclist_squat"],
            availableEquipment: ["Kettlebell", "Slant Board"],
            constraints: [
                ResolvedConstraint(
                    constraintType: "BodyRegion",
                    value: "left_knee",
                    hard: true,
                    sourceText: "left knee"
                )
            ]
        )

        let receipt = try XCTUnwrap(receipts.first)
        XCTAssertEqual(receipt.decision, "filtered")
        XCTAssertTrue(receipt.reasonCodes.contains("ACTIVE_KNEE_RESTRICTION"))
        XCTAssertTrue(receipt.graphPaths.contains("BodyRegion:left_knee -PART_OF-> BodyRegion:knee"))
    }
}
