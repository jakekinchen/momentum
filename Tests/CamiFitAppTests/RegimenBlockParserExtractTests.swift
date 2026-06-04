import XCTest
@testable import CamiFitApp

final class RegimenBlockParserExtractTests: XCTestCase {
    func testExtractsBothBlockKindsFromMixedProse() {
        let text = """
        Here is a plan!
        ```camifit-routine
        {"id":"r1"}
        ```
        And a new move:
        ```camifit-exercise
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
}
