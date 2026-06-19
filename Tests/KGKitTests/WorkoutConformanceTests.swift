import XCTest
@testable import KGKit

final class WorkoutConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct MC: Decodable {
            let constraint_type: String, value: String, hard: Bool, negated: Bool
            let laterality: String?, graph_paths: [String], source_text: String
            let safety_behavior: String?, resolution_status: String
            let confidence: Double, resolution_method: String
        }
        struct Rx: Decodable {
            let exercise_id: String, name: String
            let sets: Int?, reps: String?, rest_seconds: Int?, duration_seconds: Int?
        }
        struct Alt: Decodable { let filtered_exercise_id: String, alternative_exercise_id: String, score: Double }
        struct Expected: Decodable {
            let warmup: [Rx], main: [Rx], cooldown: [Rx]
            let selected_ids: [String], filtered_ids: [String], alternatives: [Alt]
        }
        let prompt: String, minutes: Int, available_equipment: [String]
        let member_constraints: [MC], expected: Expected
    }

    func testSwiftGeneratorMatchesOracle() throws {
        let a = try ArtifactLoader.bundled()
        let engine = SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
        let url = Bundle.module.url(forResource: "workout_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        XCTAssertGreaterThan(vectors.count, 0)
        for v in vectors {
            let mc = v.member_constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, graphPaths: $0.graph_paths,
                                   negated: $0.negated, laterality: $0.laterality,
                                   resolutionStatus: $0.resolution_status, safetyBehavior: $0.safety_behavior,
                                   confidence: $0.confidence, resolutionMethod: $0.resolution_method)
            }
            let plan = try WorkoutGenerator.generateWorkout(
                engine: engine, prompt: v.prompt, minutes: v.minutes,
                availableEquipment: v.available_equipment, memberConstraints: mc)
            let ctx = v.prompt
            assertConstraints(Array(plan.resolvedConstraints.suffix(mc.count)), mc, "\(ctx)/member constraints")
            func assertRx(_ got: [Prescription], _ exp: [Vector.Rx], _ which: String) {
                XCTAssertEqual(got.count, exp.count, "\(ctx)/\(which) count")
                for (g, e) in zip(got, exp) {
                    XCTAssertEqual(g.exerciseID, e.exercise_id, "\(ctx)/\(which) id")
                    XCTAssertEqual(g.sets, e.sets, "\(ctx)/\(which) sets")
                    XCTAssertEqual(g.reps, e.reps, "\(ctx)/\(which) reps")
                    XCTAssertEqual(g.restSeconds, e.rest_seconds, "\(ctx)/\(which) rest")
                    XCTAssertEqual(g.durationSeconds, e.duration_seconds, "\(ctx)/\(which) dur")
                }
            }
            assertRx(plan.warmup, v.expected.warmup, "warmup")
            assertRx(plan.main, v.expected.main, "main")
            assertRx(plan.cooldown, v.expected.cooldown, "cooldown")
            XCTAssertEqual(plan.selectedExercises.map { $0.exerciseID }, v.expected.selected_ids, "\(ctx)/selected")
            XCTAssertEqual(plan.filteredExercises.map { $0.exerciseID }, v.expected.filtered_ids, "\(ctx)/filtered")
            XCTAssertEqual(plan.alternatives.count, v.expected.alternatives.count, "\(ctx)/alt count")
            for (g, e) in zip(plan.alternatives, v.expected.alternatives) {
                XCTAssertEqual(g.filteredExerciseID, e.filtered_exercise_id, ctx)
                XCTAssertEqual(g.alternativeExerciseID, e.alternative_exercise_id, ctx)
                XCTAssertEqual(g.score, e.score, "\(ctx)/alt score")
            }
        }
    }

    private func assertConstraints(_ got: [ResolvedConstraint], _ exp: [ResolvedConstraint], _ ctx: String) {
        XCTAssertEqual(got.count, exp.count, "\(ctx) count")
        for (g, e) in zip(got, exp) {
            XCTAssertEqual(g.constraintType, e.constraintType, ctx)
            XCTAssertEqual(g.value, e.value, ctx)
            XCTAssertEqual(g.hard, e.hard, ctx)
            XCTAssertEqual(g.sourceText, e.sourceText, ctx)
            XCTAssertEqual(g.graphPaths, e.graphPaths, ctx)
            XCTAssertEqual(g.verified, e.verified, ctx)
            XCTAssertEqual(g.negated, e.negated, ctx)
            XCTAssertEqual(g.laterality, e.laterality, ctx)
            XCTAssertEqual(g.resolutionStatus, e.resolutionStatus, ctx)
            XCTAssertEqual(g.safetyBehavior, e.safetyBehavior, ctx)
            XCTAssertEqual(g.confidence, e.confidence, accuracy: 0.000_001, ctx)
            XCTAssertEqual(g.resolutionMethod, e.resolutionMethod, ctx)
        }
    }
}
