import CamiFitEngine
import XCTest
@testable import CamiFitApp

final class RoutinePresentationTests: XCTestCase {
    func testFutureFoundationSummaryUsesExerciseLanguageAndDurationEstimate() {
        let summary = RoutinePresentation.summary(for: FutureRoutineCatalog.foundationRoutine, compiler: Self.compiler)

        XCTAssertTrue(summary.isRunnable)
        XCTAssertEqual(summary.exerciseCount, 4)
        XCTAssertEqual(summary.exerciseCountText, "4 exercises")
        XCTAssertEqual(summary.setCount, 4)
        XCTAssertEqual(summary.durationText, "About 5 min")
        XCTAssertEqual(summary.compactDetailText, "4 exercises · About 5 min")
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
