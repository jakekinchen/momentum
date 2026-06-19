import CamiFitEngine
import XCTest
@testable import CamiFitApp

final class RoutineCompilerTests: XCTestCase {
    func testCompilerExpandsRoutineIntoExecutableSets() throws {
        let routine = WorkoutRoutine(
            id: "leg-day",
            name: "Leg Day",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 2, reps: 5, restSeconds: 30)
            ]
        )

        let executable = try Self.compiler.compile(routine)

        XCTAssertEqual(executable.blocks.count, 1)
        XCTAssertEqual(executable.blocks[0].sets.count, 2)
        XCTAssertEqual(executable.blocks[0].target, .reps(5))
        XCTAssertEqual(executable.blocks[0].sets.map(\.target), [.reps(5), .reps(5)])
        XCTAssertEqual(executable.blocks[0].sets.map(\.restSecondsAfterSet), [30, 30])
    }

    func testCompilerRejectsInvalidRoutineShape() throws {
        XCTAssertThrowsError(try Self.compiler.compile(WorkoutRoutine(id: "empty", name: "Empty", blocks: []))) { error in
            XCTAssertEqual(error as? RoutineValidationError, .emptyRoutine)
        }

        let badSets = WorkoutRoutine(
            id: "bad-sets",
            name: "Bad Sets",
            blocks: [RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 0, reps: 5)]
        )
        XCTAssertThrowsError(try Self.compiler.compile(badSets)) { error in
            XCTAssertEqual(error as? RoutineValidationError, .nonpositiveSets(block: 0, sets: 0))
        }

        let bothTargets = WorkoutRoutine(
            id: "both",
            name: "Both",
            blocks: [RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 5, holdSeconds: 20)]
        )
        XCTAssertThrowsError(try Self.compiler.compile(bothTargets)) { error in
            XCTAssertEqual(error as? RoutineValidationError, .bothTargets(block: 0))
        }
    }

    func testCompilerRejectsMissingPresetAndIncompatibleTarget() throws {
        let missingPreset = WorkoutRoutine(
            id: "missing",
            name: "Missing",
            blocks: [RoutineBlock(exerciseRef: .preset(id: "missing_preset"), sets: 1, reps: 5)]
        )
        XCTAssertThrowsError(try Self.compiler.compile(missingPreset)) { error in
            XCTAssertEqual(error as? RoutineValidationError, .missingPreset(block: 0, id: "missing_preset"))
        }

        let incompatible = WorkoutRoutine(
            id: "bad-target",
            name: "Bad Target",
            blocks: [RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 1, reps: 5)]
        )
        XCTAssertThrowsError(try Self.compiler.compile(incompatible)) { error in
            guard case .incompatibleTarget(block: 0, message: _) = error as? RoutineValidationError else {
                return XCTFail("Expected incompatible target, got \(error)")
            }
        }
    }

    func testCompilerUsesHoldDefaultForHoldPresetWithoutRoutineOverride() throws {
        let routine = WorkoutRoutine(
            id: "hold-default",
            name: "Hold Default",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 1)
            ]
        )

        let executable = try Self.compiler.compile(routine)

        XCTAssertEqual(executable.blocks.first?.target, .holdSeconds(1.0))
    }

    func testCompilerRejectsCatalogOnlyRoutineBlock() throws {
        let routine = WorkoutRoutine(
            id: "catalog-only",
            name: "Catalog Only",
            blocks: [
                RoutineBlock(
                    exerciseRef: .catalog(
                        id: "Exercise:bench_lying_single_arm_dumbbell_tricep_extension",
                        name: "Bench-Lying Single-Arm Dumbbell Tricep Extension"
                    ),
                    sets: 3,
                    reps: 10,
                    guidance: RoutineBlockGuidance(
                        status: "recommend_only",
                        displayText: "No guide yet"
                    )
                )
            ]
        )

        XCTAssertThrowsError(try Self.compiler.compile(routine)) { error in
            XCTAssertEqual(
                error as? RoutineValidationError,
                .unguidedCatalogExercise(block: 0, name: "Bench-Lying Single-Arm Dumbbell Tricep Extension")
            )
        }
        XCTAssertNil(routine.guidedOnly())
    }

    func testCompilerRejectsInlineRoutineBlockUntilMotionReferencePromotion() throws {
        let program = try ProgramLoader.load(from: Self.presetsDirectory.appendingPathComponent("bodyweight_squat.json"))
        let routine = WorkoutRoutine(
            id: "inline-squat",
            name: "Inline Squat",
            blocks: [
                RoutineBlock(exerciseRef: .inline(program), sets: 1, reps: 10)
            ]
        )

        XCTAssertThrowsError(try Self.compiler.compile(routine)) { error in
            XCTAssertEqual(
                error as? RoutineValidationError,
                .invalidInlineExercise(
                    block: 0,
                    message: "Inline exercises require accepted motion-reference promotion before guided execution"
                )
            )
        }
        XCTAssertNil(routine.guidedOnly())
    }

    func testCompilerRejectsMixedRoutineUntilGuidedSubsetIsUsed() throws {
        let routine = WorkoutRoutine(
            id: "mixed-guided-and-catalog",
            name: "Mixed Guided And Catalog",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 10),
                RoutineBlock(
                    exerciseRef: .catalog(
                        id: "Exercise:bench_lying_single_arm_dumbbell_tricep_extension",
                        name: "Bench-Lying Single-Arm Dumbbell Tricep Extension"
                    ),
                    sets: 3,
                    reps: 10,
                    guidance: RoutineBlockGuidance(
                        status: "recommend_only",
                        displayText: "No guide yet",
                        note: "Reference capture is required before this exercise can run."
                    )
                )
            ]
        )

        XCTAssertThrowsError(try Self.compiler.compile(routine)) { error in
            XCTAssertEqual(
                error as? RoutineValidationError,
                .unguidedCatalogExercise(block: 1, name: "Bench-Lying Single-Arm Dumbbell Tricep Extension")
            )
        }

        let guidedRoutine = try XCTUnwrap(routine.guidedOnly())
        XCTAssertEqual(guidedRoutine.blocks.count, 1)
        XCTAssertTrue(
            AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs.isDisjoint(
                with: Self.presetIDs(in: guidedRoutine)
            )
        )

        let executable = try Self.compiler.compile(guidedRoutine)
        XCTAssertEqual(executable.blocks.map(\.program.id), ["bodyweight_squat"])
    }

    private static let compiler = RoutineCompiler { presetID in
        try ProgramLoader.load(from: presetsDirectory.appendingPathComponent("\(presetID).json"))
    }

    private static func presetIDs(in routine: WorkoutRoutine) -> Set<String> {
        Set(routine.blocks.compactMap { block in
            guard case let .preset(id) = block.exerciseRef else { return nil }
            return id
        })
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetsDirectory: URL {
        packageRoot.appendingPathComponent("Presets")
    }
}
