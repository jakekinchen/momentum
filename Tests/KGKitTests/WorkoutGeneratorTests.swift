import XCTest
@testable import KGKit

final class WorkoutGeneratorTests: XCTestCase {
    private func graph() throws -> LocalGraph { try LocalGraph(artifact: try ArtifactLoader.bundled()) }

    func testCandidateIdsLowerBodyFilter() throws {
        let g = try graph()
        let all = g.nodesByType("Exercise").map { $0.id }
        let lower = WorkoutGenerator.candidateIds("lower body / knee focus", g)
        XCTAssertFalse(lower.isEmpty)
        XCTAssertTrue(lower.allSatisfy { all.contains($0) })
        XCTAssertTrue(lower.allSatisfy { WorkoutGenerator.isLowerBodyCandidate(g, $0) })
        XCTAssertEqual(WorkoutGenerator.candidateIds("anything", g), all)
    }

    func testPrescriptionRepsVsDuration() throws {
        let g = try graph()
        let anyExercise = g.nodesByType("Exercise").first!.id
        let p = WorkoutGenerator.prescription(g, anyExercise, "main")
        if p.sets != nil {
            XCTAssertEqual(p.sets, 3); XCTAssertEqual(p.restSeconds, 75)
            XCTAssertNotNil(p.reps); XCTAssertNil(p.durationSeconds)
        } else {
            XCTAssertEqual(p.durationSeconds, 60); XCTAssertEqual(p.restSeconds, 30)
            XCTAssertNil(p.reps)
        }
        XCTAssertEqual(p.exerciseID, anyExercise)
    }

    func testWorkoutSectionsSlicingAndSort() throws {
        let g = try graph()
        let ids = g.nodesByType("Exercise").map { $0.id }
        let selected = ids.prefix(7).map { id in
            DecisionReceipt(exerciseID: id, decision: "selected", primarySeverity: "BOOST",
                            reasonCodes: ["PASSED_SAFETY"], primaryReasonCode: "PASSED_SAFETY",
                            graphPaths: [], constraintFingerprint: "f", graphVersion: "v",
                            rulesetVersion: "v", ontologyLockVersion: "v") }
        let s = WorkoutGenerator.workoutSections(g, Array(selected))
        XCTAssertLessThanOrEqual(s.main.count, 5)
        let scores = s.main.map { WorkoutGenerator.priorityScore(g, $0.exerciseID) }
        XCTAssertEqual(scores, scores.sorted(by: >))
    }
}
