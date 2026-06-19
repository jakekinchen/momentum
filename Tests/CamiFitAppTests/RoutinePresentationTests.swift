import CamiFitEngine
import XCTest
@testable import CamiFitApp

final class RoutinePresentationTests: XCTestCase {
    func testFutureFoundationSummaryUsesExerciseLanguageAndDurationEstimate() {
        let summary = RoutinePresentation.summary(for: FutureRoutineCatalog.foundationRoutine, compiler: Self.compiler)

        XCTAssertTrue(summary.isRunnable)
        XCTAssertEqual(summary.exerciseCount, 3)
        XCTAssertEqual(summary.exerciseCountText, "3 exercises")
        XCTAssertEqual(summary.setCount, 3)
        XCTAssertEqual(summary.durationText, "About 3 min")
        XCTAssertEqual(summary.compactDetailText, "3 exercises · About 3 min")
    }

    func testExerciseSummaryPrefersHoldTargetForHoldPreset() throws {
        let program = try ProgramLoader.load(from: Self.presetsDirectory.appendingPathComponent("bodyweight_plank.json"))
        let summary = RoutinePresentation.summary(for: program)

        XCTAssertEqual(SetTarget.defaultTarget(for: program), .holdSeconds(1.0))
        XCTAssertEqual(summary.kindText, "Timed hold")
        XCTAssertEqual(summary.targetText, "1s hold")
    }

    func testRoutineEstimateIncludesGuidesCountdownsWorkAndBetweenExerciseRest() throws {
        let routine = WorkoutRoutine(
            id: "estimate",
            name: "Estimate",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 10, restSeconds: 30),
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 1, holdSeconds: 20, restSeconds: 0)
            ]
        )
        let executable = try Self.compiler.compile(routine)

        XCTAssertEqual(RoutinePresentation.estimatedSeconds(for: executable), 98)
        XCTAssertEqual(RoutinePresentation.durationText(seconds: 98), "About 2 min")
    }

    func testSummaryTreatsCatalogRowsAsPartialGuidedRoutine() {
        let routine = WorkoutRoutine(
            id: "partial",
            name: "Partial",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 10, restSeconds: 30),
                RoutineBlock(
                    exerciseRef: .catalog(
                        id: "Exercise:bench_lying_single_arm_dumbbell_tricep_extension",
                        name: "Bench-Lying Single-Arm Dumbbell Tricep Extension"
                    ),
                    sets: 3,
                    reps: 10,
                    guidance: RoutineBlockGuidance(status: "recommend_only", displayText: "No guide yet")
                )
            ]
        )

        let summary = RoutinePresentation.summary(for: routine, compiler: Self.compiler)

        XCTAssertTrue(summary.isRunnable)
        XCTAssertEqual(summary.exerciseCount, 2)
        XCTAssertEqual(summary.setCount, 4)
        XCTAssertEqual(summary.compactDetailText, "2 exercises · About 3 min · Guided subset")
        XCTAssertEqual(summary.availabilityText, "1 exercise has no guide yet; guided start will use the exercises with packaged motion data.")
    }

    func testSummarySkipsStaleReferenceCapturePresetWhenGuideReadySubsetCanRun() {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        let compiler = RoutineCompiler { presetID in
            try viewModel.programForPreset(id: presetID)
        }
        let routine = WorkoutRoutine(
            id: "mixed-stale-pike",
            name: "Mixed Stale Pike",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 10),
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_pike"), sets: 1, reps: 8)
            ]
        )

        let summary = RoutinePresentation.summary(for: routine, compiler: compiler)

        XCTAssertTrue(summary.isRunnable)
        XCTAssertEqual(summary.exerciseCount, 2)
        XCTAssertEqual(summary.setCount, 2)
        XCTAssertEqual(summary.compactDetailText, "2 exercises · About 1 min · Guided subset")
        XCTAssertEqual(summary.availabilityText, "1 exercise has no guide yet; guided start will use the exercises with packaged motion data.")
    }

    func testSummaryTreatsReferenceCapturePresetRoutineAsUnavailable() {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        let compiler = RoutineCompiler { presetID in
            try viewModel.programForPreset(id: presetID)
        }
        let routine = WorkoutRoutine(
            id: "stale-pike-preset",
            name: "Stale Pike Preset",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_pike"), sets: 1, reps: 8)
            ]
        )

        let summary = RoutinePresentation.summary(for: routine, compiler: compiler)

        XCTAssertFalse(summary.isRunnable)
        XCTAssertEqual(summary.compactDetailText, "1 exercise · About 33s · Unavailable")
        XCTAssertEqual(summary.availabilityText, "Exercise 1 uses an unavailable preset: bodyweight_pike.")
    }

    func testSummaryTreatsInlineRoutineAsUnavailableUntilMotionReferencePromotion() throws {
        let program = try ProgramLoader.load(from: Self.presetsDirectory.appendingPathComponent("bodyweight_squat.json"))
        let routine = WorkoutRoutine(
            id: "inline-squat",
            name: "Inline Squat",
            blocks: [
                RoutineBlock(exerciseRef: .inline(program), sets: 1, reps: 10)
            ]
        )

        let summary = RoutinePresentation.summary(for: routine, compiler: Self.compiler)

        XCTAssertFalse(summary.isRunnable)
        XCTAssertEqual(summary.compactDetailText, "1 exercise · About 39s · Unavailable")
        XCTAssertEqual(
            summary.availabilityText,
            "Exercise 1 inline exercise is not runnable: Inline exercises require accepted motion-reference promotion before guided execution."
        )
    }

    private static let compiler = RoutineCompiler { presetID in
        try ProgramLoader.load(from: presetsDirectory.appendingPathComponent("\(presetID).json"))
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
