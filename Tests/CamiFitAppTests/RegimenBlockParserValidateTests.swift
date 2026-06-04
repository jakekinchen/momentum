import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RegimenBlockParserValidateTests: XCTestCase {
    private func squatJSON() throws -> String {
        let url = Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!
        return String(data: try Data(contentsOf: url), encoding: .utf8)!
    }
    func testValidExerciseDecodesAndDryRuns() throws {
        let result = RegimenBlockParser.validateExercise(json: try squatJSON())
        guard case let .success(program) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(program.id, "bodyweight_squat")
    }
    func testMalformedJSONFails() {
        let result = RegimenBlockParser.validateExercise(json: "{ not json")
        guard case .failure = result else { return XCTFail("expected failure") }
    }
}
