import XCTest
@testable import CamiFitApp

@MainActor
final class TrainingContextPanelTests: XCTestCase {
    func testFormCheckRepProgressStartsFromCurrentBaseline() {
        let controller = FormCheckController()
        var state = AppExerciseSessionState(selectedExerciseID: "squat", selectedExerciseName: "Squat", repCount: 4)

        controller.begin(current: state)
        XCTAssertEqual(controller.progress(for: state, target: .reps(10)), 0)

        state.repCount = 5
        XCTAssertEqual(controller.progress(for: state, target: .reps(10)), 1)
    }

    func testFormCheckHoldProgressUsesShortMatchWindow() {
        let controller = FormCheckController()
        var state = AppExerciseSessionState(selectedExerciseID: "plank", selectedExerciseName: "Plank", holdSeconds: 10)

        controller.begin(current: state)
        state.holdSeconds = 11.5
        XCTAssertEqual(controller.progress(for: state, target: .holdSeconds(30)), 0.5, accuracy: 0.001)

        state.holdSeconds = 13
        XCTAssertEqual(controller.progress(for: state, target: .holdSeconds(30)), 1, accuracy: 0.001)
    }

    func testTrainingTimelineStageClassification() {
        XCTAssertEqual(TrainingTimelineStage.classify(title: "Hip circle warm-up"), .warmup)
        XCTAssertEqual(TrainingTimelineStage.classify(title: "Bodyweight Squat", exerciseID: "bodyweight_squat"), .work)
        XCTAssertEqual(TrainingTimelineStage.classify(title: "Cool-down stretch"), .cooldown)
    }
}
