import XCTest
@testable import KGKit

final class SeverityLatticeTests: XCTestCase {
    func testPrimarySeverityPicksMostSevere() {
        XCTAssertEqual(Severity.primary(["EQUIPMENT_HARD_BLOCK", "MEDICAL_HARD_BLOCK"]), "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(Severity.primary(["SOFT_PENALTY", "PROMPT_EXCLUSION"]), "PROMPT_EXCLUSION")
        XCTAssertNil(Severity.primary(["NOT_A_SEVERITY"]))
    }

    func testHardBlockSet() {
        XCTAssertTrue(Severity.isHardBlock("EQUIPMENT_HARD_BLOCK"))
        XCTAssertFalse(Severity.isHardBlock("SOFT_PENALTY"))
    }
}
