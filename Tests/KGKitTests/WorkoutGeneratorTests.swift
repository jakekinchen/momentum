import XCTest
@testable import KGKit

final class WorkoutGeneratorTests: XCTestCase {
    private func graph() throws -> LocalGraph { try LocalGraph(artifact: try ArtifactLoader.bundled()) }
    private func assessmentGraph() throws -> LocalGraph {
        try LocalGraph(artifact: try ArtifactLoader.assessmentBundled())
    }

    func testCandidateIdsLowerBodyFilter() throws {
        let g = try graph()
        let all = g.nodesByType("Exercise")
            .map { $0.id }
            .filter { !WorkoutGenerator.quarantinedExerciseIDs.contains($0) }
        let lower = WorkoutGenerator.candidateIds("lower body / knee focus", g)
        XCTAssertFalse(lower.isEmpty)
        XCTAssertTrue(lower.allSatisfy { all.contains($0) })
        XCTAssertTrue(lower.allSatisfy { WorkoutGenerator.isLowerBodyCandidate(g, $0) })
        XCTAssertEqual(WorkoutGenerator.candidateIds("anything", g), all)
    }

    func testCandidateIdsUseWordAwareRowAndLatFilters() throws {
        let g = try assessmentGraph()
        let all = g.nodesByType("Exercise")
            .map { $0.id }
            .filter { !WorkoutGenerator.quarantinedExerciseIDs.contains($0) }
        let row = WorkoutGenerator.candidateIds("upper-back row routine", g)
        let flatBench = WorkoutGenerator.candidateIds("arms tricep extension with flat bench", g)

        XCTAssertTrue(row.contains("Exercise:single_arm_chest_supported_incline_row"))
        XCTAssertTrue(row.allSatisfy { id in
            g.outgoing(id, predicate: "VARIANT_OF").contains { $0.target == "ExerciseFamily:row_family" }
                || g.outgoing(id, predicate: "TARGETS").contains {
                    $0.target == "MuscleGroup:upper_back" || $0.target == "MuscleGroup:lats"
                }
        })
        XCTAssertEqual(flatBench, all)
    }

    func testExactAssessmentExercisePromptsTargetEveryGoldenExercise() throws {
        let artifact = try ArtifactLoader.assessmentBundled()
        let graph = try LocalGraph(artifact: artifact)
        let engine = SafetyEngine(graph: graph, rules: artifact.safetyRules)
        let allEquipment = graph.nodesByType("Equipment").map(\.id)

        for exercise in graph.nodesByType("Exercise") {
            let prompt = "Build a routine focused on \(exercise.label)."
            if WorkoutGenerator.quarantinedExerciseIDs.contains(exercise.id) {
                XCTAssertEqual(WorkoutGenerator.candidateIds(prompt, graph), [], exercise.id)
                continue
            }

            XCTAssertEqual(WorkoutGenerator.candidateIds(prompt, graph), [exercise.id], exercise.id)

            let plan = try WorkoutGenerator.generateWorkout(
                engine: engine,
                prompt: prompt,
                minutes: 20,
                availableEquipment: allEquipment,
                memberConstraints: []
            )
            let sectionIDs = (plan.warmup + plan.main + plan.cooldown).map(\.exerciseID)

            XCTAssertEqual(plan.selectedExercises.map(\.exerciseID), [exercise.id], exercise.id)
            XCTAssertTrue(sectionIDs.contains(exercise.id), exercise.id)
        }
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
