import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RoutineInlineExerciseTests: XCTestCase {
    func testStartRoutineWithInlineExerciseSavesAndSelectsIt() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let program = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        // Build a routine that references the program inline. Encode via ExerciseRef.inline.
        let block = RoutineBlock(exerciseRef: .inline(program), sets: 3, reps: 10, holdSeconds: nil, restSeconds: 60)
        let routine = WorkoutRoutine(id: "r-inline", name: "Inline", description: "x", blocks: [block])
        try vm.saveGeneratedExercise(program, store: store) // ensure dir exists / mirrors real flow
        try vm.startRoutine(routine)
        XCTAssertEqual(vm.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertTrue(vm.availablePresets.contains { $0.id == "bodyweight_squat" })
    }
}
