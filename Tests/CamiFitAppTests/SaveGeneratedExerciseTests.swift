import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class SaveGeneratedExerciseTests: XCTestCase {
    func testSavedGuideReadyIDElectiveDraftDoesNotShadowBundledPreset() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let squat = try ProgramLoader.load(from: Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "json",
            subdirectory: "Presets"
        )!)
        let generated = ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: squat.id,
            name: "Generated Shadow Squat",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: squat.signals,
            filters: squat.filters,
            validity: squat.validity,
            rep: squat.rep,
            hold: squat.hold,
            formRules: squat.formRules,
            set: squat.set
        )

        try vm.saveGeneratedExercise(generated, store: store)

        XCTAssertFalse(vm.availablePresets.contains { $0.id == "bodyweight_squat" })
        XCTAssertThrowsError(try vm.selectPreset(id: "bodyweight_squat")) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetNotFound("bodyweight_squat"))
        }
    }

    func testSavedUnknownExerciseDoesNotBecomeTrackableWithoutGuideApproval() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let squat = try ProgramLoader.load(from: Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "json",
            subdirectory: "Presets"
        )!)
        let generated = ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: "generated_no_reference_trace",
            name: "Generated No Reference Trace",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: squat.signals,
            filters: squat.filters,
            validity: squat.validity,
            rep: squat.rep,
            hold: squat.hold,
            formRules: squat.formRules,
            set: squat.set
        )

        try vm.saveGeneratedExercise(generated, store: store)

        XCTAssertFalse(vm.availablePresets.contains { $0.id == generated.id })
        XCTAssertEqual(vm.trackingReadiness(forPresetID: generated.id), nil)
        XCTAssertThrowsError(try vm.selectPreset(id: generated.id)) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetNotFound(generated.id))
        }
    }

    func testGeneratedProgramCannotBypassPresetSelectionThroughDirectActivation() throws {
        let vm = AppExerciseSessionViewModel()
        vm.loadAvailablePresets()
        let initiallySelected = vm.state.selectedExerciseID
        let squat = try ProgramLoader.load(from: Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "json",
            subdirectory: "Presets"
        )!)
        let generated = ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: squat.id,
            name: "Generated Shadow Squat",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: squat.signals,
            filters: squat.filters,
            validity: squat.validity,
            rep: squat.rep,
            hold: squat.hold,
            formRules: squat.formRules,
            set: squat.set
        )

        XCTAssertThrowsError(try vm.activateProgram(generated)) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture("bodyweight_squat"))
        }
        XCTAssertEqual(vm.state.selectedExerciseID, initiallySelected)
    }

    func testGeneratedProgramCannotBypassPresetSelectionThroughFrameResult() throws {
        let vm = AppExerciseSessionViewModel()
        vm.loadAvailablePresets()
        let initiallySelected = vm.state.selectedExerciseID
        let squat = try ProgramLoader.load(from: Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "json",
            subdirectory: "Presets"
        )!)
        let generated = ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: "generated_no_reference_trace",
            name: "Generated No Reference Trace",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: squat.signals,
            filters: squat.filters,
            validity: squat.validity,
            rep: squat.rep,
            hold: squat.hold,
            formRules: squat.formRules,
            set: squat.set
        )
        let frameURL = try XCTUnwrap(Bundle.module.url(
            forResource: "synthetic_squat_demo",
            withExtension: "jsonl",
            subdirectory: "Demo"
        ))
        let frame = try XCTUnwrap(MediaPipePoseJSONLDecoder.decode(contentsOf: frameURL).first)
        var session = try ExerciseExecutionSession(program: squat, target: .reps(1))
        let result = session.ingest(frame)

        XCTAssertThrowsError(try vm.applyExerciseFrameResult(result, program: generated)) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture(generated.id))
        }
        XCTAssertEqual(vm.state.selectedExerciseID, initiallySelected)
    }
}
