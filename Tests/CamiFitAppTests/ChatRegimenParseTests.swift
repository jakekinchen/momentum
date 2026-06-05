import XCTest
@testable import CamiFitApp

final class ChatRegimenParseTests: XCTestCase {
    func testParseAttachesExerciseCardToMessage() throws {
        let squat = try String(contentsOf: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let text = "Try this:\n```camifit-exercise\n\(squat)\n```"
        let results = RegimenBlockParser.parse(message: text)
        XCTAssertEqual(results.count, 1)
        if case .exercise = results[0] {} else { XCTFail("expected exercise result") }
    }
}
