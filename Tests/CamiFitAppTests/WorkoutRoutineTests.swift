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

    func testRejectsWrongRoutineArtifactType() {
        let json = """
        {"schemaVersion":1,"artifactType":"meal","id":"r1","name":"Leg Day","blocks":[]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutRoutine.self, from: json))
    }
}
