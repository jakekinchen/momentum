import XCTest
@testable import KGKit

final class ResolvedConstraintFieldsTests: XCTestCase {
    func testDefaultsMatchPythonDataclass() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "knee", hard: false, sourceText: "knee")
        XCTAssertEqual(c.graphPaths, [])
        XCTAssertFalse(c.verified)
        XCTAssertEqual(c.resolutionStatus, "resolved")
        XCTAssertNil(c.safetyBehavior)
    }
    func testRichConstruction() {
        let c = ResolvedConstraint(constraintType: "Equipment", value: "kettlebell", hard: true,
                                   sourceText: "only kettlebell", graphPaths: ["a -X-> b"],
                                   safetyBehavior: "allowed_equipment_only")
        XCTAssertEqual(c.graphPaths, ["a -X-> b"])
        XCTAssertEqual(c.safetyBehavior, "allowed_equipment_only")
        XCTAssertEqual(c.nodeID, "Equipment:kettlebell")
    }
    func testBackwardCompatibleInit() {
        let c = ResolvedConstraint(constraintType: "Equipment", value: "barbell", hard: true,
                                   sourceText: "no barbell", negated: true)
        XCTAssertTrue(c.negated)
        XCTAssertEqual(c.resolutionStatus, "resolved")
    }
}
