import XCTest
@testable import CamiFitApp

final class RegimenBlockParserCRLFTests: XCTestCase {
    func testExtractsBlockWithCRLFLineEndings() {
        let text = "intro\r\n```camifit-exercise\r\n{\"id\":\"e1\"}\r\n```\r\nbye"
        let blocks = RegimenBlockParser.extractBlocks(from: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .exercise)
    }
}
