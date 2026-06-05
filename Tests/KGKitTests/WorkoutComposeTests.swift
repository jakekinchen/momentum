import XCTest
@testable import KGKit

final class WorkoutComposeTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let a = try ArtifactLoader.bundled()
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testGenerateLowerBodyAvoidingKnee() throws {
        let e = try engine()
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true,
                                      sourceText: "left knee active injury", safetyBehavior: "block_if_safety_critical")
        let plan = try WorkoutGenerator.generateWorkout(
            engine: e, prompt: "lower body, knee-safe", minutes: 50,
            availableEquipment: ["Equipment:dumbbell", "Equipment:kettlebell", "Equipment:yoga_mat"],
            memberConstraints: [knee])
        XCTAssertEqual(plan.timeWindowMinutes, 50)
        XCTAssertEqual(plan.availableEquipment, ["Equipment:dumbbell", "Equipment:kettlebell", "Equipment:yoga_mat"])
        let selected = Set(plan.selectedExercises.map { $0.exerciseID })
        let filtered = Set(plan.filteredExercises.map { $0.exerciseID })
        XCTAssertTrue(selected.isDisjoint(with: filtered))
        XCTAssertLessThanOrEqual(plan.main.count, 5)
        for alt in plan.alternatives { XCTAssertTrue(selected.contains(alt.alternativeExerciseID)) }
        XCTAssertTrue(plan.resolvedConstraints.contains { $0.value == "left_knee" })
    }
}
