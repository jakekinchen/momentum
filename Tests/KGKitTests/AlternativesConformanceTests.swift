import XCTest
@testable import KGKit

final class AlternativesConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct C: Decodable { let constraint_type: String, value: String, hard: Bool, source_text: String, negated: Bool }
        struct Alt: Decodable {
            let filtered_exercise_id: String, alternative_exercise_id: String, derived_from: String
            let score: Double, score_components: [String: Double], graph_paths: [String]
        }
        let available_equipment: [String]; let constraints: [C]; let expected_alternatives: [Alt]
    }

    func testSwiftAlternativesMatchOracle() throws {
        let artifact = try ArtifactLoader.bundled()
        let g = try LocalGraph(artifact: artifact)
        let engine = SafetyEngine(graph: g, rules: artifact.safetyRules)
        let url = Bundle.module.url(forResource: "alternatives_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        for v in vectors {
            let constraints = v.constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, negated: $0.negated)
            }
            let receipts = try engine.evaluateCandidates(availableEquipment: v.available_equipment, constraints: constraints)
            let got = try Alternatives.selectAlternatives(receipts, availableEquipment: v.available_equipment, graph: g)
            XCTAssertEqual(got.count, v.expected_alternatives.count)
            for (a, e) in zip(got, v.expected_alternatives) {
                XCTAssertEqual(a.filteredExerciseID, e.filtered_exercise_id)
                XCTAssertEqual(a.alternativeExerciseID, e.alternative_exercise_id, "selected alt for \(e.filtered_exercise_id)")
                XCTAssertEqual(a.derivedFrom, e.derived_from)
                XCTAssertEqual(a.score, e.score, "score for \(e.filtered_exercise_id) -> \(e.alternative_exercise_id)")
                XCTAssertEqual(a.graphPaths, e.graph_paths)
                for (k, ev) in e.score_components { XCTAssertEqual(a.scoreComponents[k], ev, k) }
            }
        }
    }
}
