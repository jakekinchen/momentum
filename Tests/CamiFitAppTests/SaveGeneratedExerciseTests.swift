import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class SaveGeneratedExerciseTests: XCTestCase {
    func testSavedExerciseBecomesSelectable() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let squat = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        try vm.saveGeneratedExercise(squat, store: store)
        XCTAssertTrue(vm.availablePresets.contains { $0.id == "bodyweight_squat" })
    }
}
