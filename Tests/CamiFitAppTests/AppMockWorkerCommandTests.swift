import XCTest
@testable import CamiFitApp

final class AppMockWorkerCommandTests: XCTestCase {
    func testMockWorkerCommandFeedsSummaryHUDAndOverlayState() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runMockWorkerProvider(
            workerScriptURL: Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py"),
            selectedPresetID: "bodyweight_squat",
            fixture: "squat_bottom",
            frameID: 35,
            timestampMS: 3_500
        )

        XCTAssertEqual(summary.frameCount, 1)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertEqual(summary.latestPoseFrame?.timestampMS, 3_500)
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertEqual(viewModel.latestHUDState?.frameCount, 1)
        XCTAssertGreaterThan(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-mock-worker-command selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) hud_frames=\(viewModel.latestHUDState?.frameCount.description ?? "nil") " +
            "overlay_points=\(viewModel.latestPoseOverlayState.points.count) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMockWorkerCommandMissingPathSurfacesDeterministicDiagnostic() {
        let viewModel = AppExerciseSessionViewModel()
        let missingWorker = Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")

        let summary = viewModel.runMockWorkerProvider(workerScriptURL: missingWorker)

        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertTrue(summary.diagnosticText?.contains("Pose provider failed") == true)
        XCTAssertTrue(summary.diagnosticText?.contains("pose worker script not found: \(missingWorker.path)") == true)
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertEqual(viewModel.latestHUDState?.frameCount, 0)
        XCTAssertEqual(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-mock-worker-command-missing selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) hud_frames=\(viewModel.latestHUDState?.frameCount.description ?? "nil") " +
            "diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testDefaultMockWorkerScriptURLIsRepoLocal() {
        let url = AppExerciseSessionViewModel.defaultMockWorkerScriptURL(currentDirectory: Self.packageRoot)

        XCTAssertEqual(url, Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py"))

        print("app-mock-worker-command-default-url path=\(url.path)")
    }

    func testPackagedDefaultMockWorkerScriptURLUsesBundleResources() {
        let launchDirectory = URL(fileURLWithPath: "/Users/kelly/Documents")
        let resources = URL(fileURLWithPath: "/Applications/Momentum.app/Contents/Resources", isDirectory: true)
        let url = AppExerciseSessionViewModel.defaultMockWorkerScriptURL(
            currentDirectory: launchDirectory,
            bundleURL: URL(fileURLWithPath: "/Applications/Momentum.app", isDirectory: true),
            resourceURL: resources
        )

        XCTAssertEqual(url, resources.appendingPathComponent("pose_worker/pose_worker.py"))
        XCTAssertFalse(url.path.hasPrefix(launchDirectory.path))

        print("app-mock-worker-command-packaged-url path=\(url.path)")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
