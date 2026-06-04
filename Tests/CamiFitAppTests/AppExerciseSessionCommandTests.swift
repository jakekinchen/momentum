import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class AppExerciseSessionCommandTests: XCTestCase {
    func testRecordedProviderCommandRunsSelectedSquatThroughAdapterAndUpdatesSummary() {
        let viewModel = AppExerciseSessionViewModel()
        let provider = MediaPipePoseProvider(jsonlURL: Self.twoFrameFixtureURL)

        let summary = viewModel.runRecordedProvider(provider, selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 2)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertEqual(summary.holdSeconds, 0)
        XCTAssertFalse(summary.holdTargetReached)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertEqual(viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertNotNil(viewModel.resolvedPresetSourceURL)
        XCTAssertTrue(viewModel.resolvedPresetSourceURL?.path.contains("CamiFit_CamiFitApp.bundle/Presets") == true)

        print(
            "app-command-squat fixture=mediapipe_pose_worker_two_frames.jsonl " +
            "source=\(viewModel.resolvedPresetSourceURL?.path ?? "nil") selected=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testRecordedProviderCommandUsesCurrentSelectionWhenPresetIDIsOmitted() throws {
        let viewModel = AppExerciseSessionViewModel()
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_squat")
        let provider = MediaPipePoseProvider(jsonlURL: Self.mixedNoPoseFixtureURL)

        let summary = viewModel.runRecordedProvider(provider)

        XCTAssertEqual(summary.frameCount, 3)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertTrue(summary.diagnosticText?.contains("missing landmark primary.hip") == true)
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)

        print(
            "app-command-current-selection fixture=mediapipe_pose_worker_mixed_no_pose.jsonl " +
            "selected=\(summary.selectedExerciseID ?? "nil") frames=\(summary.frameCount) " +
            "reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testRecordedProviderCommandSurfacesProviderFailureDiagnostic() {
        let viewModel = AppExerciseSessionViewModel()
        let provider = CommandThrowingPoseProvider(error: CommandProviderFailure.message("recorded fixture unreadable"))

        let summary = viewModel.runRecordedProvider(provider, selectedPresetID: "bodyweight_squat")

        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertTrue(summary.diagnosticText?.contains("Pose provider failed") == true)
        XCTAssertTrue(summary.diagnosticText?.contains("recorded fixture unreadable") == true)
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)

        print(
            "app-command-provider-failure selected=\(summary.selectedExerciseID ?? "nil") " +
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

private struct CommandThrowingPoseProvider: PoseProvider {
    let error: Error

    func frames() throws -> [PoseFrame] {
        throw error
    }
}

private enum CommandProviderFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}
