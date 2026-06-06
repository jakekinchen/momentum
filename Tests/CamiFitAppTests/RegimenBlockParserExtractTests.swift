import XCTest
@testable import CamiFitApp

final class RegimenBlockParserExtractTests: XCTestCase {
    func testExtractsBothBlockKindsFromMixedProse() {
        let text = """
        Here is a plan!
        ```future-routine
        {"id":"r1"}
        ```
        And a new move:
        ```future-exercise
        {"id":"e1"}
        ```
        Enjoy.
        """
        let blocks = RegimenBlockParser.extractBlocks(from: text)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .routine)
        XCTAssertEqual(blocks[0].json, "{\"id\":\"r1\"}")
        XCTAssertEqual(blocks[1].kind, .exercise)
    }
    func testNoBlocksReturnsEmpty() {
        XCTAssertTrue(RegimenBlockParser.extractBlocks(from: "just text").isEmpty)
    }

    func testLegacyCamiFitTagsStillParse() {
        let text = """
        ```camifit-routine
        {"id":"r1"}
        ```
        """
        let blocks = RegimenBlockParser.extractBlocks(from: text)
        XCTAssertEqual(blocks.map(\.kind), [.routine])
    }

    func testDisplayTextRemovesRoutineAndExerciseBlocks() {
        let text = """
        Here is a plan.
        ```future-routine
        {"id":"r1"}
        ```
        And a move:
        ```future-exercise
        {"id":"e1"}
        ```
        Use controlled reps.
        """

        let visible = RegimenBlockParser.displayText(removingBlocks: text)

        XCTAssertTrue(visible.contains("Here is a plan."))
        XCTAssertTrue(visible.contains("Use controlled reps."))
        XCTAssertFalse(visible.contains("future-routine"))
        XCTAssertFalse(visible.contains("future-exercise"))
        XCTAssertFalse(visible.contains("\"id\""))
    }
}
