import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class WorkoutRoutineTests: XCTestCase {
    func testDecodesRoutineWithPresetRef() throws {
        let json = """
        {"schemaVersion":1,"artifactType":"routine","id":"r1","name":"Leg Day","description":"x",
         "blocks":[{"exerciseRef":{"preset":"bodyweight_squat"},"sets":3,"reps":10,"restSeconds":60}]}
        """.data(using: .utf8)!
        let routine = try JSONDecoder().decode(WorkoutRoutine.self, from: json)
        XCTAssertEqual(routine.schemaVersion, 1)
        XCTAssertEqual(routine.artifactType, "routine")
        XCTAssertEqual(routine.blocks.count, 1)
        XCTAssertEqual(routine.blocks[0].sets, 3)
        if case let .preset(id) = routine.blocks[0].exerciseRef { XCTAssertEqual(id, "bodyweight_squat") }
        else { XCTFail("expected preset ref") }
    }

    func testDecodesLegacyRoutineWithoutArtifactFields() throws {
        let json = """
        {"id":"r1","name":"Leg Day",
         "blocks":[{"exerciseRef":{"preset":"bodyweight_squat"},"sets":3,"reps":10}]}
        """.data(using: .utf8)!
        let routine = try JSONDecoder().decode(WorkoutRoutine.self, from: json)
        XCTAssertEqual(routine.schemaVersion, 1)
        XCTAssertEqual(routine.artifactType, "routine")
    }

    func testDecodesCatalogOnlyRoutineBlock() throws {
        let json = """
        {"schemaVersion":1,"artifactType":"routine","id":"r1","name":"Catalog Plan",
         "blocks":[{"exerciseRef":{"catalog":{"id":"Exercise:bench_lying_single_arm_dumbbell_tricep_extension","name":"Bench-Lying Single-Arm Dumbbell Tricep Extension"}},"sets":3,"reps":10,"guidance":{"status":"recommend_only","displayText":"No guide yet","note":"Motion data pending"}}]}
        """.data(using: .utf8)!
        let routine = try JSONDecoder().decode(WorkoutRoutine.self, from: json)

        XCTAssertEqual(routine.blocks.count, 1)
        XCTAssertTrue(routine.hasUnguidedBlocks)
        XCTAssertEqual(routine.blocks[0].guidance?.displayText, "No guide yet")
        if case let .catalog(id, name) = routine.blocks[0].exerciseRef {
            XCTAssertEqual(id, "Exercise:bench_lying_single_arm_dumbbell_tricep_extension")
            XCTAssertEqual(name, "Bench-Lying Single-Arm Dumbbell Tricep Extension")
        } else {
            XCTFail("expected catalog ref")
        }
    }

    func testRejectsWrongRoutineArtifactType() {
        let json = """
        {"schemaVersion":1,"artifactType":"meal","id":"r1","name":"Leg Day","blocks":[]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutRoutine.self, from: json))
    }
}
