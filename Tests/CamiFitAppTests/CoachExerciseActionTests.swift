import XCTest
@testable import CamiFitApp

@MainActor
final class CoachExerciseActionTests: XCTestCase {
    func testCoachActionParserFindsGuideActionAndStripsToolBlockFromVisibleText() throws {
        let assistantText = """
        I can show you the squat guide now.

        ```future-coach-action
        {"schemaVersion":1,"tool":"activate_exercise","exerciseID":"bodyweight_squat","mode":"guide","reason":"User asked to see squat form"}
        ```
        """

        let actions = CoachActionParser.parse(message: assistantText)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].exerciseID, "bodyweight_squat")
        XCTAssertEqual(actions[0].mode, .guide)
        XCTAssertEqual(actions[0].reason, "User asked to see squat form")
        XCTAssertEqual(
            CoachActionParser.displayText(removingActionBlocks: assistantText)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "I can show you the squat guide now."
        )
    }

    func testShowMeSquatActionActivatesGuideWithoutStartingRoutine() throws {
        let harness = try CoachActionHarness()
        let action = CoachExerciseAction(
            exerciseID: "bodyweight_squat",
            mode: .guide,
            reason: "Show me how to do a squat"
        )

        let result = harness.dispatcher.apply(action)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(harness.modeController.current?.mode, .guide)
        XCTAssertEqual(harness.runner.runScope, .exercise)
        XCTAssertEqual(harness.runner.phase, .guide(secondsRemaining: 6))
    }

    func testCheckMySquatFormActionActivatesMatchFormMode() throws {
        let harness = try CoachActionHarness()
        let action = CoachExerciseAction(
            exerciseID: "bodyweight_squat",
            mode: .matchForm,
            reason: "Check my form on a squat"
        )

        let result = harness.dispatcher.apply(action)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(harness.modeController.current?.mode, .matchForm)
        XCTAssertEqual(harness.runner.runScope, .exercise)
        XCTAssertEqual(harness.runner.phase, .preparing)
    }

    func testChatFinishPathDispatchesCoachActionAndHidesRawToolJSON() throws {
        let harness = try CoachActionHarness()
        let chat = ChatViewModel()
        chat.coachActionDispatcher = harness.dispatcher
        let assistantText = """
        Let's check your squat form.

        ```future-coach-action
        {"schemaVersion":1,"tool":"activate_exercise","exerciseID":"bodyweight_squat","mode":"match_form","reason":"User asked for a squat form check"}
        ```
        """

        chat.appendCompletedAssistantResponse(assistantText, sourceUserText: "Can you check my form on a squat?")

        XCTAssertEqual(chat.messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines), "Let's check your squat form.")
        XCTAssertEqual(chat.messages.last?.coachActionArtifacts.first?.status, .succeeded)
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertEqual(harness.modeController.current?.mode, .matchForm)
        XCTAssertEqual(harness.runner.runScope, .exercise)
        XCTAssertEqual(harness.runner.phase, .preparing)
    }

    func testInvalidExerciseActionFailsClosedWithoutChangingSelectedExercise() throws {
        let harness = try CoachActionHarness()
        try harness.viewModel.selectPreset(id: "bodyweight_squat")
        let action = CoachExerciseAction(
            exerciseID: "unsupported_barbell_back_squat",
            mode: .matchForm,
            reason: "Check my form"
        )

        let result = harness.dispatcher.apply(action)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.detail.contains("unsupported_barbell_back_squat"))
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertNil(harness.modeController.current)
    }

    func testReferenceCaptureRequiredActionFailsClosedWithoutChangingSelectedExercise() throws {
        let harness = try CoachActionHarness()
        try harness.viewModel.selectPreset(id: "bodyweight_squat")
        let action = CoachExerciseAction(
            exerciseID: "resistance_band_reverse_curl",
            mode: .guide,
            reason: "Show me a reverse curl"
        )

        let result = harness.dispatcher.apply(action)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.detail.contains("licensed reference clip"))
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertNil(harness.modeController.current)
    }

    func testRejectedJumpingJackActionFailsClosedWithoutChangingSelectedExercise() throws {
        let harness = try CoachActionHarness()
        try harness.viewModel.selectPreset(id: "bodyweight_squat")
        let action = CoachExerciseAction(
            exerciseID: "bodyweight_jumping_jack",
            mode: .guide,
            reason: "Show me a jumping jack"
        )

        let result = harness.dispatcher.apply(action)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.detail.contains("licensed reference clip"))
        XCTAssertEqual(harness.viewModel.state.selectedExerciseID, "bodyweight_squat")
        XCTAssertNil(harness.modeController.current)
    }
}

@MainActor
private struct CoachActionHarness {
    let viewModel: AppExerciseSessionViewModel
    let runner: RoutineRunner
    let modeController: ExerciseModeController
    let dispatcher: CoachActionDispatcher

    init() throws {
        viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)
        modeController = ExerciseModeController()
        dispatcher = CoachActionDispatcher(
            viewModel: viewModel,
            routineRunner: runner,
            modeController: modeController
        )
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetsDirectory: URL {
        packageRoot.appendingPathComponent("Presets")
    }
}
