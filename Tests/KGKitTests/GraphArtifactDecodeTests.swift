import XCTest
@testable import KGKit

final class GraphArtifactDecodeTests: XCTestCase {
    static let json = """
    {
      "graph_version": "fitgraph-kg-m5-validation-v0",
      "ruleset_version": "ruleset-m2-safety-v0",
      "ontology_lock_version": "ontology-lock-m0-unverified",
      "nodes": [
        {"id": "BodyRegion:knee", "type": "BodyRegion", "label": "knee", "aliases": ["knee"], "properties": {"laterality": "neutral"}},
        {"id": "BodyRegion:left_knee", "type": "BodyRegion", "label": "left knee", "aliases": ["left knee"], "properties": {"laterality": "left"}},
        {"id": "Exercise:goblet_squat", "type": "Exercise", "label": "Goblet Squat", "aliases": [], "properties": {"priority_score": 0.7}}
      ],
      "edges": [
        {"source": "BodyRegion:left_knee", "predicate": "PART_OF", "target": "BodyRegion:knee", "properties": {"runtime_safety_edge": true}},
        {"source": "Exercise:goblet_squat", "predicate": "STRESSES", "target": "BodyRegion:left_knee", "properties": {"loaded": true, "flexion_depth": "deep", "load_level": "high"}}
      ],
      "safety_rules": [
        {"id": "SafetyRule:avoid_loaded_knee_flexion", "severity": "MEDICAL_HARD_BLOCK", "reason_code": "ACTIVE_KNEE_RESTRICTION", "uses_concepts": ["BodyRegion:knee"], "match": {"edge_predicate": "STRESSES", "properties": {"loaded": true, "flexion_depth": ["deep"], "load_level": ["medium", "high"]}}}
      ]
    }
    """

    func testDecodesNodesEdgesAndRules() throws {
        let artifact = try GraphArtifact.decode(from: Data(Self.json.utf8))
        XCTAssertEqual(artifact.graphVersion, "fitgraph-kg-m5-validation-v0")
        XCTAssertEqual(artifact.nodes.count, 3)
        XCTAssertEqual(artifact.edges.count, 2)
        XCTAssertEqual(artifact.safetyRules.count, 1)
        let stress = artifact.edges.first { $0.predicate == "STRESSES" }!
        XCTAssertEqual(stress.properties["loaded"], .bool(true))
        XCTAssertEqual(stress.properties["flexion_depth"], .string("deep"))
        let rule = artifact.safetyRules[0]
        XCTAssertEqual(rule.reasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(rule.usesConcepts, ["BodyRegion:knee"])
        XCTAssertEqual(rule.matchEdgePredicate, "STRESSES")
        XCTAssertEqual(rule.matchProperties["flexion_depth"], .anyOf(["deep"]))
        XCTAssertEqual(rule.matchProperties["loaded"], .exact(.bool(true)))
    }
}
