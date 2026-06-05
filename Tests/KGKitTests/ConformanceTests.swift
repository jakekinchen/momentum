import XCTest
@testable import KGKit

final class ConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct Constraint: Decodable {
            let constraint_type: String, value: String, hard: Bool, source_text: String, negated: Bool
        }
        struct Input: Decodable {
            let available_equipment: [String]; let constraints: [Constraint]; let exercise_id: String
        }
        struct Expected: Decodable {
            let decision: String, primary_severity: String
            let reason_codes: [String], primary_reason_code: String, graph_paths: [String]
            let constraint_fingerprint: String, graph_version: String, ruleset_version: String, ontology_lock_version: String
        }
        let scenario: String, input: Input, expected: Expected
    }

    func testSwiftRuntimeReproducesEveryOracleReceipt() throws {
        let artifact = try ArtifactLoader.bundled()
        let engine = SafetyEngine(graph: try LocalGraph(artifact: artifact), rules: artifact.safetyRules)

        let url = Bundle.module.url(forResource: "safety_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let payload = try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url))
        let vectors = payload["vectors"] ?? []
        XCTAssertGreaterThan(vectors.count, 0, "no vectors loaded")

        for v in vectors {
            let constraints = v.input.constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, negated: $0.negated)
            }
            let got = try engine.evaluateCandidates([v.input.exercise_id],
                availableEquipment: v.input.available_equipment, constraints: constraints)[0]
            let e = v.expected
            let ctx = "\(v.scenario)/\(v.input.exercise_id)"
            XCTAssertEqual(got.decision, e.decision, ctx)
            XCTAssertEqual(got.primarySeverity, e.primary_severity, ctx)
            XCTAssertEqual(got.reasonCodes, e.reason_codes, ctx)
            XCTAssertEqual(got.primaryReasonCode, e.primary_reason_code, ctx)
            XCTAssertEqual(got.graphPaths, e.graph_paths, ctx)
            XCTAssertEqual(got.constraintFingerprint, e.constraint_fingerprint, "FINGERPRINT \(ctx)")
            XCTAssertEqual(got.graphVersion, e.graph_version, ctx)
            XCTAssertEqual(got.rulesetVersion, e.ruleset_version, ctx)
            XCTAssertEqual(got.ontologyLockVersion, e.ontology_lock_version, ctx)
        }
    }
}
