import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class AppPoseProviderSessionTests: XCTestCase {
    func testRecordedMediaPipeFramesReachDefaultPresetAppSessionForSquat() throws {
        let provider = MediaPipePoseProvider(jsonlURL: Self.twoFrameFixtureURL)
        let viewModel = AppExerciseSessionViewModel()
        let session = AppPoseProviderSession(provider: provider, viewModel: viewModel)

        let summary = session.run(selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 2)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertEqual(summary.holdSeconds, 0)
        XCTAssertFalse(summary.holdTargetReached)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertNotNil(viewModel.resolvedPresetSourceURL)
        XCTAssertTrue(viewModel.resolvedPresetSourceURL?.path.contains("CamiFit_CamiFitApp.bundle/Presets") == true)

        print(
            "app-pose-provider-squat fixture=mediapipe_pose_worker_two_frames.jsonl " +
            "source=\(viewModel.resolvedPresetSourceURL?.path ?? "nil") selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMixedNoPoseFixtureFailsClosedWithoutFalseSquatCount() {
        let provider = MediaPipePoseProvider(jsonlURL: Self.mixedNoPoseFixtureURL)
        let viewModel = AppExerciseSessionViewModel()
        let session = AppPoseProviderSession(provider: provider, viewModel: viewModel)

        let summary = session.run(selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 3)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertTrue(summary.diagnosticText?.contains("missing landmark primary.hip") == true)

        print(
            "app-pose-provider-no-pose fixture=mediapipe_pose_worker_mixed_no_pose.jsonl " +
            "selected=\(summary.selectedExerciseID ?? "nil") frames=\(summary.frameCount) " +
            "reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testThrowingProviderReturnsClearDiagnosticWithoutCrashing() {
        let provider = ThrowingPoseProvider(error: ProviderFailure.message("fixture unavailable"))
        let session = AppPoseProviderSession(provider: provider, viewModel: AppExerciseSessionViewModel())

        let summary = session.run(selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertTrue(summary.diagnosticText?.contains("Pose provider failed") == true)
        XCTAssertTrue(summary.diagnosticText?.contains("fixture unavailable") == true)

        print(
            "app-pose-provider-throwing selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var twoFrameFixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl")
    }

    private static var mixedNoPoseFixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl")
    }
}

private struct ThrowingPoseProvider: PoseProvider {
    let error: Error

    func frames() throws -> [PoseFrame] {
        throw error
    }
}

private enum ProviderFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}
