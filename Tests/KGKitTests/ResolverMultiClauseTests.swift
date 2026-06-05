import XCTest
@testable import KGKit

final class ResolverMultiClauseTests: XCTestCase {
    private func graph() throws -> LocalGraph { try LocalGraph(artifact: try ArtifactLoader.bundled()) }

    func testSingleClauseShortCircuits() throws {
        let cs = try Resolver.resolveText("no barbell", graph: try graph())
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].value, "barbell")
    }

    func testMultiClauseSkipsRequestShapeAndResolvesRest() throws {
        let cs = try Resolver.resolveText("Build a session. No barbell. Exclude deadlifts.", graph: try graph())
        let values = Set(cs.map { $0.value })
        XCTAssertTrue(values.contains("barbell"))
        XCTAssertTrue(values.contains("deadlift_family"))
        XCTAssertFalse(cs.contains { $0.constraintType == "UnresolvedConcept" })
    }

    func testAllUnresolvedMultiClauseReturnsUnresolved() throws {
        let cs = try Resolver.resolveText("Frobnicate the wibble. Glorp the snarf.", graph: try graph())
        XCTAssertTrue(cs.allSatisfy { $0.constraintType == "UnresolvedConcept" })
    }
}
