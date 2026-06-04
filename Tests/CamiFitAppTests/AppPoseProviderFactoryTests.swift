import XCTest
@testable import CamiFitApp

final class AppPoseProviderFactoryTests: XCTestCase {
    func testRecordedRunModeUsesCatalogProviderAndPreservesRecordedBehavior() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runConfiguredPoseProvider(mode: .recordedRun(id: "squat_two_frames"))

        XCTAssertEqual(summary.frameCount, 2)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertEqual(viewModel.selectedRecordedRunID, "squat_two_frames")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertTrue(viewModel.resolvedRecordedRunSourceURL?.path.contains("CamiFit_CamiFitApp.bundle/RecordedRuns") == true)

        print(
            "app-provider-factory-recorded mode=squat_two_frames selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) " +
            "source=\(viewModel.resolvedRecordedRunSourceURL?.path ?? "nil") diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMockWorkerModeFeedsAppSessionAndOverlayState() {
        let viewModel = AppExerciseSessionViewModel()
        let configuration = AppMockWorkerPoseProviderConfiguration(
            workerScriptURL: Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py"),
            selectedPresetID: "bodyweight_squat",
            fixture: "squat_bottom",
            frameID: 34,
            timestampMS: 3_400
        )

        let summary = viewModel.runConfiguredPoseProvider(mode: .mockWorker(configuration))

        XCTAssertEqual(summary.frameCount, 1)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertEqual(summary.latestPoseFrame?.timestampMS, 3_400)
        XCTAssertGreaterThan(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-provider-factory-mock fixture=squat_bottom selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) " +
            "overlay_points=\(viewModel.latestPoseOverlayState.points.count) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMockWorkerMissingPathSurfacesDeterministicRunDiagnostic() {
        let viewModel = AppExerciseSessionViewModel()
        let missingWorker = Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")
        let configuration = AppMockWorkerPoseProviderConfiguration(workerScriptURL: missingWorker)

        let summary = viewModel.runConfiguredPoseProvider(mode: .mockWorker(configuration))

        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertTrue(summary.diagnosticText?.contains("Pose provider failed") == true)
        XCTAssertTrue(summary.diagnosticText?.contains("pose worker script not found: \(missingWorker.path)") == true)
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertEqual(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-provider-factory-missing-worker selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMissingRecordedRunModeSurfacesDeterministicConfigurationDiagnostic() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runConfiguredPoseProvider(mode: .recordedRun(id: "missing-recorded-run"))

        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertNil(summary.selectedExerciseID)
        XCTAssertEqual(summary.diagnosticText, "Pose provider configuration failed: recorded run not found: missing-recorded-run")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)

        print(
            "app-provider-factory-missing-recorded frames=\(summary.frameCount) " +
            "diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
