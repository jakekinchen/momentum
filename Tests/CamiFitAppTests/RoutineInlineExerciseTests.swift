import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RoutineInlineExerciseTests: XCTestCase {
    func testStartRoutineWithInlineExerciseRequiresReferencePromotion() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let program = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let block = RoutineBlock(exerciseRef: .inline(program), sets: 3, reps: 10, holdSeconds: nil, restSeconds: 60)
        let routine = WorkoutRoutine(id: "r-inline", name: "Inline", description: "x", blocks: [block])

        XCTAssertThrowsError(try vm.startRoutine(routine)) { error in
            guard case let .invalidInlineExercise(message) = error as? AppExerciseSessionError else {
                return XCTFail("Expected invalidInlineExercise, got \(error)")
            }
            XCTAssertTrue(message.contains("motion-reference promotion"))
        }
        XCTAssertNil(vm.state.selectedExerciseID)
        XCTAssertFalse(block.isGuideAvailable)
    }
}
