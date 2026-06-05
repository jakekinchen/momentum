import XCTest
@testable import KGKit

final class LocalGraphTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        let artifact = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return try LocalGraph(artifact: artifact)
    }

    func testOutgoingFiltersByPredicate() throws {
        let g = try graph()
        let stresses = g.outgoing("Exercise:goblet_squat", predicate: "STRESSES")
        XCTAssertEqual(stresses.map { $0.target }, ["BodyRegion:left_knee"])
        XCTAssertEqual(g.outgoing("Exercise:goblet_squat", predicate: "REQUIRES").count, 0)
    }

    func testNodesByTypeAndUnknownNodeThrows() throws {
        let g = try graph()
        XCTAssertEqual(g.nodesByType("Exercise").map { $0.id }, ["Exercise:goblet_squat"])
        XCTAssertThrowsError(try g.requireNode("Exercise:nope"))
    }

    func testDuplicateNodeIDsRejected() {
        let dup = """
        {"graph_version":"v","ruleset_version":"v","ontology_lock_version":"v",
         "nodes":[{"id":"A","type":"X","label":"a"},{"id":"A","type":"X","label":"a"}],
         "edges":[],"safety_rules":[]}
        """
        XCTAssertThrowsError(try LocalGraph(artifact: try GraphArtifact.decode(from: Data(dup.utf8))))
    }
}
