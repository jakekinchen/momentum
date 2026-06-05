import XCTest
@testable import KGKit

final class ResolverTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        try LocalGraph(artifact: try ArtifactLoader.bundled())
    }

    func testNormalizeCollapsesAndStrips() {
        XCTAssertEqual(Resolver.normalize("  No   Barbell!! "), "no barbell")
        XCTAssertEqual(Resolver.normalize("(Kettlebell)"), "kettlebell")
    }

    func testNoBarbellNegatedEquipment() throws {
        let cs = try Resolver.resolveSingleClause("no barbell", graph: try graph())
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].constraintType, "Equipment")
        XCTAssertEqual(cs[0].value, "barbell")
        XCTAssertTrue(cs[0].hard); XCTAssertTrue(cs[0].negated)
    }

    func testExcludeDeadliftsFamily() throws {
        let cs = try Resolver.resolveSingleClause("exclude deadlifts", graph: try graph())
        XCTAssertEqual(cs[0].constraintType, "ExerciseFamily")
        XCTAssertEqual(cs[0].value, "deadlift_family")
        XCTAssertTrue(cs[0].negated)
    }

    func testLeftKneeHasLateralityAndPath() throws {
        let cs = try Resolver.resolveSingleClause("left knee", graph: try graph())
        XCTAssertEqual(cs[0].value, "left_knee")
        XCTAssertEqual(cs[0].laterality, "left")
        XCTAssertEqual(cs[0].graphPaths, ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }

    func testOnlyEquipmentSubset() throws {
        let cs = try Resolver.resolveSingleClause("only dumbbells and kettlebell", graph: try graph())
        XCTAssertEqual(cs.map { $0.constraintType }, ["Equipment", "Equipment"])
        XCTAssertEqual(Set(cs.map { $0.value }), ["dumbbell", "kettlebell"])
        XCTAssertTrue(cs.allSatisfy { $0.hard && $0.safetyBehavior == "allowed_equipment_only" })
    }

    func testUnknownTermIsUnresolvedHard() throws {
        let cs = try Resolver.resolveSingleClause("xyzzy", graph: try graph())
        XCTAssertEqual(cs[0].constraintType, "UnresolvedConcept")
        XCTAssertTrue(cs[0].hard)
        XCTAssertEqual(cs[0].resolutionStatus, "needs_review")
        XCTAssertEqual(cs[0].safetyBehavior, "ask_clarification")
    }
}
