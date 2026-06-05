import XCTest
@testable import KGKit

final class AlternativesScoringTests: XCTestCase {
    func testRoundTo6() {
        XCTAssertEqual(Alternatives.roundTo6(0.1 + 0.2), 0.3)
        XCTAssertEqual(Alternatives.roundTo6(0.45 * (1.0/3.0)), 0.15)
        XCTAssertEqual(Alternatives.roundTo6(0.12345678), 0.123457) // rounds up at the 7th decimal (not a tie)
    }

    func testWeightedScoreComposesWeights() {
        let s = Alternatives.weightedScore([
            "target_overlap": 1.0, "movement_pattern_similarity": 1.0,
            "equipment_preference": 1.0, "priority_tier": 0.5,
        ])
        XCTAssertEqual(s, Alternatives.roundTo6(0.45 + 0.35 + 0.10 + 0.05))
        XCTAssertEqual(s, 0.95)
    }
}
