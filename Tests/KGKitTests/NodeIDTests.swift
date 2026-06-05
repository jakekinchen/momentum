import XCTest
@testable import KGKit

final class NodeIDTests: XCTestCase {
    func testNodeIDNormalization() {
        XCTAssertEqual(NodeID.make("Equipment", "Kettlebell"), "Equipment:kettlebell")
        XCTAssertEqual(NodeID.make("BodyRegion", "left knee"), "BodyRegion:left_knee")
        XCTAssertEqual(NodeID.make("Equipment", "Equipment:barbell"), "Equipment:barbell") // already-prefixed passthrough
    }

    func testConstraintDefaults() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true, sourceText: "left knee")
        XCTAssertFalse(c.negated)
        XCTAssertNil(c.laterality)
    }
}
