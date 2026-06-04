import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class PoseWorkerSubprocessProviderTests: XCTestCase {
    func testMockWorkerHealthAndPredictDecodePoseFrame() throws {
        let provider = Self.mockProvider(frameID: 42, timestampMS: 1_234, fixture: "standing")

        let health = try provider.health()
        let frames = try provider.frames()
        let frame = try XCTUnwrap(frames.first)

        XCTAssertTrue(health.ok)
        XCTAssertTrue(health.poseReady)
        XCTAssertEqual(health.runningMode, "VIDEO")
        XCTAssertTrue(health.message.contains("mock mode ready"))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frame.timestampMS, 1_234)
        XCTAssertEqual(frame.imageWidth, 1_280)
        XCTAssertEqual(frame.imageHeight, 720)
        XCTAssertNotNil(frame.landmark(named: "primary.knee"))
        XCTAssertEqual(frame.landmarks.count, 37)

        print(
            "pose-worker-mock-health command=\(provider.launchCommandDescription) " +
            "ok=\(health.ok) pose_ready=\(health.poseReady) mode=\(health.runningMode) message=\(health.message)"
        )
        print(
            "pose-worker-mock-frame frame_id=42 timestamp=\(frame.timestampMS) size=\(frame.imageWidth)x\(frame.imageHeight) " +
            "landmarks=\(frame.landmarks.count) primary_knee=\(String(describing: frame.landmark(named: "primary.knee")))"
        )
    }

    func testMockWorkerPoseFrameFeedsAppSessionCommandPath() {
        let provider = Self.mockProvider(frameID: 7, timestampMS: 2_000, fixture: "squat_bottom")
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedProvider(provider, selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 1)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertNotNil(summary.latestPoseFrame)
        XCTAssertGreaterThan(viewModel.latestPoseOverlayState.points.count, 0)

        print(
            "pose-worker-mock-app-path selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) " +
            "overlay_points=\(viewModel.latestPoseOverlayState.points.count) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMissingWorkerPathFailsDeterministicallyWithoutLaunch() {
        let missingProvider = PoseWorkerSubprocessProvider(
            workerScriptURL: Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py")
        )

        XCTAssertThrowsError(try missingProvider.frames()) { error in
            XCTAssertEqual(
                String(describing: error),
                "pose worker script not found: \(Self.packageRoot.appendingPathComponent("pose_worker/missing_pose_worker.py").path)"
            )
        }

        print("pose-worker-mock-missing-path error=pose worker script not found")
    }

    private static func mockProvider(frameID: Int, timestampMS: Int64, fixture: String) -> PoseWorkerSubprocessProvider {
        PoseWorkerSubprocessProvider(
            workerScriptURL: packageRoot.appendingPathComponent("pose_worker/pose_worker.py"),
            fixture: fixture,
            frameID: frameID,
            timestampMS: timestampMS
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
