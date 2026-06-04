import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class AppHUDOverlayStateTests: XCTestCase {
    func testCleanRecordedRunUpdatesHUDAndNonemptyOverlayState() throws {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedRun(id: "squat_two_frames")
        let hud = try XCTUnwrap(viewModel.latestHUDState)
        let overlay = viewModel.latestPoseOverlayState
        let primaryKnee = try XCTUnwrap(overlay.points.first { $0.id == "primary.knee" })

        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(hud.presetID, "bodyweight_squat")
        XCTAssertEqual(hud.presetName, "Bodyweight Squat")
        XCTAssertEqual(hud.frameCount, 2)
        XCTAssertEqual(hud.repCount, 0)
        XCTAssertNil(hud.diagnosticText)
        XCTAssertGreaterThan(overlay.points.count, 0)
        XCTAssertGreaterThan(overlay.segments.count, 0)
        XCTAssertEqual(overlay.timestampMS, summary.latestPoseFrame?.timestampMS)
        XCTAssertTrue((0 ... 1).contains(primaryKnee.x))
        XCTAssertTrue((0 ... 1).contains(primaryKnee.y))
        XCTAssertGreaterThanOrEqual(primaryKnee.confidence, 0.65)
        XCTAssertTrue(overlay.segments.contains { $0.fromID == "primary.hip" && $0.toID == "primary.knee" })

        print(
            "app-hud-overlay-clean run=squat_two_frames preset=\(hud.presetID ?? "nil") name=\(hud.presetName ?? "nil") " +
            "frames=\(hud.frameCount) reps=\(hud.repCount) points=\(overlay.points.count) segments=\(overlay.segments.count) " +
            "primary_knee=(\(primaryKnee.x),\(primaryKnee.y),confidence=\(primaryKnee.confidence)) diagnostic=\(hud.diagnosticText ?? "nil")"
        )
    }

    func testNoPoseRecordedRunPreservesHUDDiagnosticAndOmitsOverlayPoints() throws {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedRun(id: "squat_mixed_no_pose")
        let hud = try XCTUnwrap(viewModel.latestHUDState)
        let overlay = viewModel.latestPoseOverlayState

        XCTAssertEqual(summary.frameCount, 3)
        XCTAssertEqual(hud.presetID, "bodyweight_squat")
        XCTAssertEqual(hud.presetName, "Bodyweight Squat")
        XCTAssertEqual(hud.frameCount, 3)
        XCTAssertEqual(hud.repCount, 0)
        XCTAssertTrue(hud.diagnosticText?.contains("missing landmark primary.hip") == true)
        XCTAssertEqual(overlay.points, [])
        XCTAssertEqual(overlay.segments, [])

        print(
            "app-hud-overlay-no-pose run=squat_mixed_no_pose preset=\(hud.presetID ?? "nil") " +
            "frames=\(hud.frameCount) reps=\(hud.repCount) points=\(overlay.points.count) " +
            "segments=\(overlay.segments.count) diagnostic=\(hud.diagnosticText ?? "nil")"
        )
    }

    func testOverlayStateFromNoPoseFrameFailsClosedWithoutPoints() throws {
        let provider = MediaPipePoseProvider(jsonlURL: Self.mixedNoPoseFixtureURL)
        let frames = try provider.frames()
        let noPoseFrame = try XCTUnwrap(frames.first { $0.landmarks.isEmpty })

        let overlay = AppPoseOverlayState(frame: noPoseFrame)

        XCTAssertEqual(noPoseFrame.timestampMS, 2_100)
        XCTAssertEqual(overlay.timestampMS, 2_100)
        XCTAssertEqual(overlay.points, [])
        XCTAssertEqual(overlay.segments, [])

        print(
            "app-overlay-no-pose-frame timestamp=\(overlay.timestampMS ?? -1) " +
            "points=\(overlay.points.count) segments=\(overlay.segments.count)"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var mixedNoPoseFixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl")
    }
}
