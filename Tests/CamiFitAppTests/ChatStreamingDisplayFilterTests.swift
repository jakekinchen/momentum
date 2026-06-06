import XCTest
@testable import CamiFitApp

final class ChatStreamingDisplayFilterTests: XCTestCase {
    func testHidesSingleAndDoubleBacktickPrefixesAtEndOfStream() {
        XCTAssertEqual(
            ChatStreamingDisplayFilter.displayText(for: "Here is the routine.\n`"),
            "Here is the routine."
        )
        XCTAssertEqual(
            ChatStreamingDisplayFilter.displayText(for: "Here is the routine.\n``"),
            "Here is the routine."
        )
    }

    func testHidesIncompleteFutureRoutineFenceAndPayload() {
        let partial = """
        Here is the routine.

        ```future-routine
        {"schemaVersion":1,"artifactType":"routine"
        """

        XCTAssertEqual(
            ChatStreamingDisplayFilter.displayText(for: partial)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Here is the routine."
        )
    }

    func testHidesCompletedFutureRoutineBlockButKeepsFollowingText() {
        let completed = """
        Here is the routine.

        ```future-routine
        {"schemaVersion":1,"artifactType":"routine","id":"x","name":"Core","description":"Core work.","blocks":[]}
        ```

        We can tune it next.
        """

        XCTAssertEqual(
            ChatStreamingDisplayFilter.displayText(for: completed)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Here is the routine.\n\nWe can tune it next."
        )
    }

    func testShowsNonArtifactFenceOnceItIsClearlyNotAFutureArtifact() {
        let markdown = """
        Try this:
        ```swift
        print("hello")
        """

        XCTAssertEqual(ChatStreamingDisplayFilter.displayText(for: markdown), markdown)
    }

    func testHidesCoachActionAndMemoryOperationBlocks() {
        let text = """
        I can remember that and show the guide.

        ```future-kg-operation
        {"operation_type":"AddMedicalConstraint","constraint_type":"BodyRegion","value":"left_knee","source_text":"left knee pain"}
        ```

        ```future-coach-action
        {"schemaVersion":1,"tool":"activate_exercise","exerciseID":"bodyweight_plank","mode":"guide"}
        ```
        """

        XCTAssertEqual(
            ChatStreamingDisplayFilter.displayText(for: text)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "I can remember that and show the guide."
        )
    }
}
