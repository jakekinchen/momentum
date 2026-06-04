import XCTest
@testable import CamiFitApp

final class AppRecordedRunCatalogTests: XCTestCase {
    func testDefaultAppResourcesDiscoverRecordedRuns() {
        let viewModel = AppExerciseSessionViewModel()

        viewModel.loadRecordedRuns()

        XCTAssertEqual(viewModel.availableRecordedRuns.map(\.id), [
            "squat_two_frames",
            "squat_mixed_no_pose"
        ])
        XCTAssertEqual(viewModel.availableRecordedRuns.map(\.presetID), [
            "bodyweight_squat",
            "bodyweight_squat"
        ])
        XCTAssertEqual(viewModel.selectedRecordedRunID, "squat_two_frames")
        XCTAssertNotNil(viewModel.resolvedRecordedRunSourceURL)
        XCTAssertTrue(viewModel.resolvedRecordedRunSourceURL?.path.contains("CamiFit_CamiFitApp.bundle/RecordedRuns") == true)

        print(
            "app-recorded-runs source=\(viewModel.resolvedRecordedRunSourceURL?.path ?? "nil") " +
            "runs=\(viewModel.availableRecordedRuns.map { "\($0.id):\($0.presetID):\($0.purpose.rawValue)" }.joined(separator: ","))"
        )
    }

    func testCleanRecordedRunUpdatesLastSummaryThroughAppResourceCatalog() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedRun(id: "squat_two_frames")

        XCTAssertEqual(summary.frameCount, 2)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertEqual(summary.holdSeconds, 0)
        XCTAssertNil(summary.diagnosticText)
        XCTAssertEqual(viewModel.selectedRecordedRunID, "squat_two_frames")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)
        XCTAssertTrue(viewModel.resolvedRecordedRunSourceURL?.path.contains("CamiFit_CamiFitApp.bundle/RecordedRuns") == true)

        print(
            "app-recorded-run-clean id=squat_two_frames name=Squat sample source=\(viewModel.resolvedRecordedRunSourceURL?.path ?? "nil") " +
            "preset=\(summary.selectedExerciseID ?? "nil") frames=\(summary.frameCount) reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testNoPoseRecordedRunPreservesFailClosedDiagnosticEvidence() {
        let viewModel = AppExerciseSessionViewModel()

        let summary = viewModel.runRecordedRun(id: "squat_mixed_no_pose")

        XCTAssertEqual(summary.frameCount, 3)
        XCTAssertEqual(summary.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(summary.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(summary.repCount, 0)
        XCTAssertTrue(summary.diagnosticText?.contains("missing landmark primary.hip") == true)
        XCTAssertEqual(viewModel.selectedRecordedRunID, "squat_mixed_no_pose")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)

        print(
            "app-recorded-run-no-pose id=squat_mixed_no_pose name=Squat no-pose sample " +
            "source=\(viewModel.resolvedRecordedRunSourceURL?.path ?? "nil") preset=\(summary.selectedExerciseID ?? "nil") " +
            "frames=\(summary.frameCount) reps=\(summary.repCount) diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    func testMissingRecordedRunResourcesFailClosedWithDiagnostic() {
        let viewModel = AppExerciseSessionViewModel(recordedRunsDirectory: Self.packageRoot.appendingPathComponent("missing-recorded-runs"))

        viewModel.loadRecordedRuns()
        let summary = viewModel.runRecordedRun(id: "squat_two_frames")

        XCTAssertEqual(viewModel.availableRecordedRuns, [])
        XCTAssertNil(viewModel.resolvedRecordedRunSourceURL)
        XCTAssertNil(viewModel.selectedRecordedRunID)
        XCTAssertEqual(viewModel.state.diagnosticText, "No recorded runs found")
        XCTAssertEqual(summary.frameCount, 0)
        XCTAssertEqual(summary.diagnosticText, "Recorded run not found: squat_two_frames")
        XCTAssertEqual(viewModel.lastPoseProviderRunSummary, summary)

        print(
            "app-recorded-run-missing source=nil requested=squat_two_frames frames=\(summary.frameCount) " +
            "state_diagnostic=\(viewModel.state.diagnosticText ?? "nil") summary_diagnostic=\(summary.diagnosticText ?? "nil")"
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
