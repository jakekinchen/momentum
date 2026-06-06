import XCTest
@testable import CamiFitApp

final class ChatRegimenParseTests: XCTestCase {
    func testParseAttachesExerciseCardToMessage() throws {
        let squat = try String(contentsOf: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let text = "Try this:\n```future-exercise\n\(squat)\n```"
        let results = RegimenBlockParser.parse(message: text)
        XCTAssertEqual(results.count, 1)
        if case .exercise = results[0] {} else { XCTFail("expected exercise result") }
    }

    @MainActor
    func testChatHidesFutureRoutineJSONAndKeepsRoutineArtifact() throws {
        let chat = ChatViewModel()
        let text = """
        Here is a knee-friendly option.

        ```future-routine
        {"schemaVersion":1,"artifactType":"routine","id":"knee-friendly-lower-body","name":"Knee-Friendly Lower Body","description":"A gentle lower-body routine.","blocks":[{"exerciseRef":{"preset":"bodyweight_squat"},"sets":3,"reps":8,"restSeconds":75},{"exerciseRef":{"preset":"bodyweight_plank"},"sets":3,"holdSeconds":20,"restSeconds":60}]}
        ```
        """

        chat.appendCompletedAssistantResponse(text, sourceUserText: "Make my bodyweight lower body routine")

        let message = try XCTUnwrap(chat.messages.last)
        XCTAssertEqual(message.regimen.count, 1)
        XCTAssertFalse(message.text.contains("future-routine"))
        XCTAssertFalse(message.text.contains("schemaVersion"))
        XCTAssertFalse(message.text.contains("exerciseRef"))
        XCTAssertTrue(message.text.contains("Here is a knee-friendly option."))
        if case let .routine(routine) = message.regimen[0] {
            XCTAssertEqual(routine.name, "Knee-Friendly Lower Body")
            XCTAssertEqual(routine.blocks.count, 2)
        } else {
            XCTFail("expected routine artifact")
        }
    }
}
