import XCTest
@testable import KGKit

final class PartOfTraversalTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        try LocalGraph(artifact: try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8)))
    }

    func testPartOfPathLeftKneeToKnee() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:left_knee", to: "BodyRegion:knee"),
                       ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }

    func testPartOfPathSameNodeIsEmpty() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:knee", to: "BodyRegion:knee"), [])
    }

    func testPartOfPathNoConnectionIsEmpty() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:knee", to: "BodyRegion:left_knee"), [])
    }

    func testClosurePathsFromKnee() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfClosurePaths("BodyRegion:knee"),
                       ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }
}
