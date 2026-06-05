import XCTest
@testable import KGKit

final class ResolveConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct Constraint: Decodable {
            let constraint_type: String, value: String, hard: Bool, negated: Bool
            let laterality: String?, graph_paths: [String], verified: Bool
            let resolution_status: String, safety_behavior: String?
        }
        let text: String; let expected: [Constraint]
    }

    func testSwiftResolverMatchesOracle() throws {
        let graph = try LocalGraph(artifact: try ArtifactLoader.bundled())
        let url = Bundle.module.url(forResource: "resolve_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        XCTAssertGreaterThan(vectors.count, 0)
        for v in vectors {
            let got = try Resolver.resolveText(v.text, graph: graph)
            XCTAssertEqual(got.count, v.expected.count, v.text)
            for (g, e) in zip(got, v.expected) {
                XCTAssertEqual(g.constraintType, e.constraint_type, v.text)
                XCTAssertEqual(g.value, e.value, v.text)
                XCTAssertEqual(g.hard, e.hard, v.text)
                XCTAssertEqual(g.negated, e.negated, v.text)
                XCTAssertEqual(g.laterality, e.laterality, v.text)
                XCTAssertEqual(g.graphPaths, e.graph_paths, v.text)
                XCTAssertEqual(g.resolutionStatus, e.resolution_status, v.text)
                XCTAssertEqual(g.safetyBehavior, e.safety_behavior, v.text)
            }
        }
    }
}
