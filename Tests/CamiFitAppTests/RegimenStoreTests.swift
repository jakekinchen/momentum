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
}
