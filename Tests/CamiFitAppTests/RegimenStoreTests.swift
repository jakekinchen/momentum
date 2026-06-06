import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RegimenStoreTests: XCTestCase {
    func testSaveExerciseWritesJSONToUserPresets() throws {
        let store = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let squat = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let url = try store.saveExercise(squat)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try ProgramLoader.load(from: url)
        XCTAssertEqual(reloaded.id, squat.id)
    }

    func testSaveRoutineLoadsRoutineLibrary() throws {
        let store = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let routine = WorkoutRoutine(
            id: "lower-body",
            name: "Lower Body",
            description: "Bodyweight legs",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 3, reps: 10, restSeconds: 60)
            ]
        )

        let url = try store.saveRoutine(routine)
        let loaded = store.loadRoutines()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(loaded, [routine])

        print("regimen-store-routine saved=true loaded=\(loaded.count)")
    }

    func testSaveRoutineAppendsNumericSuffixOnIDCollision() throws {
        let store = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let original = WorkoutRoutine(
            id: "lower-body",
            name: "Lower Body",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 3, reps: 10)
            ]
        )
        let colliding = WorkoutRoutine(
            id: "lower-body",
            name: "Lower Body Plus",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_lunge"), sets: 2, reps: 8)
            ]
        )

        let firstURL = try store.saveRoutine(original)
        let secondURL = try store.saveRoutine(colliding)
        let loaded = store.loadRoutines()

        XCTAssertEqual(firstURL.lastPathComponent, "lower-body.json")
        XCTAssertEqual(secondURL.lastPathComponent, "lower-body-2.json")
        XCTAssertEqual(Set(loaded.map(\.id)), ["lower-body", "lower-body-2"])
    }
}
