import XCTest
@testable import KGKit

final class AlternativesSelectTests: XCTestCase {
    private func engineAndGraph() throws -> (SafetyEngine, LocalGraph) {
        let artifact = try ArtifactLoader.bundled()
        let g = try LocalGraph(artifact: artifact)
        return (SafetyEngine(graph: g, rules: artifact.safetyRules), g)
    }

    func testSelectsOneAlternativePerFilteredFromSafePool() throws {
        let (engine, g) = try engineAndGraph()
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee",
                                      hard: true, sourceText: "left knee")
        let receipts = try engine.evaluateCandidates(availableEquipment: ["Dumbbell", "Kettlebell", "Yoga Mat"],
                                                     constraints: [knee])
        let result = try Alternatives.buildWorkoutCandidates(receipts,
                            availableEquipment: ["Dumbbell", "Kettlebell", "Yoga Mat"], graph: g)
        XCTAssertEqual(result.alternatives.count, result.filteredReceipts.count)
        let selectedIDs = Set(result.selectedReceipts.map { $0.exerciseID })
        for alt in result.alternatives {
            XCTAssertTrue(selectedIDs.contains(alt.alternativeExerciseID), alt.alternativeExerciseID)
            XCTAssertEqual(alt.derivedFrom, alt.filteredExerciseID)
        }
    }

    func testNoSafePoolYieldsNoAlternatives() throws {
        let (_, g) = try engineAndGraph()
        // No "selected" receipts -> no pool to draw from (returns before touching the graph).
        let filteredOnly = [DecisionReceipt(
            exerciseID: "Exercise:x", decision: "filtered", primarySeverity: "MEDICAL_HARD_BLOCK",
            reasonCodes: ["R"], primaryReasonCode: "R", graphPaths: [], constraintFingerprint: "f",
            graphVersion: "v", rulesetVersion: "v", ontologyLockVersion: "v")]
        let alts = try Alternatives.selectAlternatives(filteredOnly, availableEquipment: [], graph: g)
        XCTAssertEqual(alts.count, 0)
    }
}
