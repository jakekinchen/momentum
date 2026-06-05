import XCTest
@testable import KGKit

final class GraphModelTests: XCTestCase {
    func testEdgePathFormatMatchesPythonEvidenceString() {
        let edge = GraphEdge(source: "BodyRegion:left_knee", predicate: "PART_OF", target: "BodyRegion:knee", properties: [:])
        XCTAssertEqual(edge.path(), "BodyRegion:left_knee -PART_OF-> BodyRegion:knee")
    }

    func testNodeKeepsAliasesAndProperties() {
        let node = GraphNode(id: "Equipment:kettlebell", type: "Equipment", label: "Kettlebell",
                             aliases: ["kettlebell", "kb"], properties: [:])
        XCTAssertEqual(node.type, "Equipment")
        XCTAssertEqual(node.aliases, ["kettlebell", "kb"])
    }
}
