import XCTest
@testable import CamiFitApp

final class AppMockWorkerPreflightTests: XCTestCase {
    func testMockWorkerPreflightSuccessReachesWorkerHealthWithoutMutatingRunState() {
        let viewModel = AppExerciseSessionViewModel()
        let workerScriptURL = Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py")

        let status = viewModel.preflightMockWorker(workerScriptURL: workerScriptURL)

        guard case let .succeeded(success) = status else {
            return XCTFail("Expected succeeded preflight, got \(status)")
        }
        XCTAssertEqual(success.workerScriptURL, workerScriptURL)
        XCTAssertTrue(success.command.contains("pose_worker.py --mode mock"))
        XCTAssertEqual(success.runningMode, "VIDEO")
        XCTAssertTrue(success.message.contains("mock mode ready"))
        XCTAssertEqual(viewModel.mockWorkerPreflightStatus, status)
        XCTAssertEqual(viewModel.poseProviderRunStatus, .idle)
        XCTAssertNil(viewModel.lastPoseProviderRunSummary)
        XCTAssertNil(viewModel.latestHUDState)
        XCTAssertEqual(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-mock-worker-preflight-success command=\(success.command) " +
            "mode=\(success.runningMode) message=\(success.message) " +
            "summary_mutated=\(viewModel.lastPoseProviderRunSummary != nil)"
        )
    }

    func testMockWorkerPreflightMissingPathFailsWithoutMutatingRunState() {
        let viewModel = AppExerciseSessionViewModel()
        let missingWorker = Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")

        let status = viewModel.preflightMockWorker(workerScriptURL: missingWorker)

        guard case let .failed(failure) = status else {
            return XCTFail("Expected failed preflight, got \(status)")
        }
        XCTAssertEqual(failure.workerScriptURL, missingWorker)
        XCTAssertEqual(failure.diagnosticText, "mock worker script not found: \(missingWorker.path)")
        XCTAssertEqual(viewModel.mockWorkerPreflightStatus, status)
        XCTAssertEqual(viewModel.poseProviderRunStatus, .idle)
        XCTAssertNil(viewModel.lastPoseProviderRunSummary)
        XCTAssertNil(viewModel.latestHUDState)
        XCTAssertEqual(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-mock-worker-preflight-missing path=\(missingWorker.path) " +
            "diagnostic=\(failure.diagnosticText) summary_mutated=\(viewModel.lastPoseProviderRunSummary != nil)"
        )
    }

    func testMockWorkerPreflightPreservesCompletedRunState() throws {
        let viewModel = AppExerciseSessionViewModel()
        let workerScriptURL = Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py")
        let missingWorker = Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")

        let completedSummary = viewModel.runMockWorkerProvider(
            workerScriptURL: workerScriptURL,
            selectedPresetID: "bodyweight_squat",
            fixture: "squat_bottom",
            frameID: 39,
            timestampMS: 3_900
        )
        let capturedSummary = try XCTUnwrap(viewModel.lastPoseProviderRunSummary)
        let capturedHUD = try XCTUnwrap(viewModel.latestHUDState)
        let capturedOverlay = viewModel.latestPoseOverlayState
        let capturedRunStatus = viewModel.poseProviderRunStatus

        XCTAssertEqual(completedSummary, capturedSummary)
        XCTAssertGreaterThan(capturedOverlay.points.count, 0)

        let successStatus = viewModel.preflightMockWorker(workerScriptURL: workerScriptURL)

        guard case .succeeded = successStatus else {
            return XCTFail("Expected succeeded preflight, got \(successStatus)")
        }
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, capturedSummary)
        XCTAssertEqual(viewModel.latestHUDState, capturedHUD)
        XCTAssertEqual(viewModel.latestPoseOverlayState, capturedOverlay)
        XCTAssertEqual(viewModel.poseProviderRunStatus, capturedRunStatus)

        let failureStatus = viewModel.preflightMockWorker(workerScriptURL: missingWorker)

        guard case let .failed(failure) = failureStatus else {
            return XCTFail("Expected failed preflight, got \(failureStatus)")
        }
        XCTAssertEqual(failure.diagnosticText, "mock worker script not found: \(missingWorker.path)")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, capturedSummary)
        XCTAssertEqual(viewModel.latestHUDState, capturedHUD)
        XCTAssertEqual(viewModel.latestPoseOverlayState, capturedOverlay)
        XCTAssertEqual(viewModel.poseProviderRunStatus, capturedRunStatus)

        print(
            "app-mock-worker-preflight-preserves-run frames=\(capturedSummary.frameCount) " +
            "overlay_points=\(capturedOverlay.points.count) run_status=\(capturedRunStatus.displayText) " +
            "success_preserved=true failure_preserved=true"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
