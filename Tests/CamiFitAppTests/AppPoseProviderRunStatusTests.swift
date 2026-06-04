import XCTest
@testable import CamiFitApp

final class AppPoseProviderRunStatusTests: XCTestCase {
    func testInitialStatusIsIdle() {
        let viewModel = AppExerciseSessionViewModel()

        XCTAssertEqual(viewModel.poseProviderRunStatus, .idle)
        XCTAssertEqual(viewModel.poseProviderRunStatus.displayText, "Provider idle")

        print("app-provider-status-initial status=\(viewModel.poseProviderRunStatus.displayText)")
    }

    func testRecordedRunSuccessUpdatesStatusWithSourceAndFrameCount() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedRun(id: "squat_two_frames")

        XCTAssertEqual(summary.frameCount, 2)
        guard case let .succeeded(statusSummary) = viewModel.poseProviderRunStatus else {
            return XCTFail("Expected succeeded status, got \(viewModel.poseProviderRunStatus)")
        }
        XCTAssertEqual(statusSummary.descriptor.mode, "recorded-run")
        XCTAssertEqual(statusSummary.descriptor.source, "recorded:squat_two_frames")
        XCTAssertEqual(statusSummary.frameCount, 2)
        XCTAssertEqual(viewModel.latestHUDState?.frameCount, 2)

        print(
            "app-provider-status-recorded mode=\(statusSummary.descriptor.mode) " +
            "source=\(statusSummary.descriptor.source) frames=\(statusSummary.frameCount)"
        )
    }

    func testMockWorkerSuccessUpdatesStatusWithSourceAndFrameCount() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runMockWorkerProvider(
            workerScriptURL: Self.packageRoot.appendingPathComponent("pose_worker/pose_worker.py"),
            selectedPresetID: "bodyweight_squat",
            fixture: "squat_bottom",
            frameID: 36,
            timestampMS: 3_600
        )

        XCTAssertEqual(summary.frameCount, 1)
        guard case let .succeeded(statusSummary) = viewModel.poseProviderRunStatus else {
            return XCTFail("Expected succeeded status, got \(viewModel.poseProviderRunStatus)")
        }
        XCTAssertEqual(statusSummary.descriptor.mode, "mock-worker")
        XCTAssertTrue(statusSummary.descriptor.source.contains("pose_worker.py --mode mock"))
        XCTAssertEqual(statusSummary.frameCount, 1)
        XCTAssertEqual(viewModel.latestHUDState?.frameCount, 1)
        XCTAssertGreaterThan(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-provider-status-mock mode=\(statusSummary.descriptor.mode) " +
            "source=\(statusSummary.descriptor.source) frames=\(statusSummary.frameCount) " +
            "overlay_points=\(viewModel.latestPoseOverlayState.points.count)"
        )
    }

    func testMissingMockWorkerUpdatesFailedStatusWithDeterministicDiagnostic() {
        let viewModel = AppExerciseSessionViewModel()
        let missingWorker = Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")

        let summary = viewModel.runMockWorkerProvider(workerScriptURL: missingWorker)

        XCTAssertEqual(summary.frameCount, 0)
        guard case let .failed(failure) = viewModel.poseProviderRunStatus else {
            return XCTFail("Expected failed status, got \(viewModel.poseProviderRunStatus)")
        }
        XCTAssertEqual(failure.descriptor.mode, "mock-worker")
        XCTAssertEqual(failure.descriptor.source, "mock-worker:/usr/bin/env python3 \(missingWorker.path) --mode mock")
        XCTAssertTrue(failure.diagnosticText.contains("pose worker script not found: \(missingWorker.path)"))
        XCTAssertEqual(viewModel.latestHUDState?.frameCount, 0)
        XCTAssertEqual(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "app-provider-status-missing-mock mode=\(failure.descriptor.mode) " +
            "source=\(failure.descriptor.source) diagnostic=\(failure.diagnosticText)"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
