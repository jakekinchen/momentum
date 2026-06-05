import XCTest
@testable import KGKit

final class EquipmentAndExclusionReasonsTests: XCTestCase {
    // Local artifact: one barbell exercise requiring a barbell, plus a deadlift variant.
    static let json = """
    {"graph_version":"v","ruleset_version":"v","ontology_lock_version":"v",
     "nodes":[
       {"id":"Equipment:barbell","type":"Equipment","label":"Barbell","aliases":["barbell"]},
       {"id":"Equipment:dumbbell","type":"Equipment","label":"Dumbbell","aliases":["dumbbell"]},
       {"id":"ExerciseFamily:deadlift_family","type":"ExerciseFamily","label":"Deadlift Family","aliases":["deadlift"]},
       {"id":"Exercise:barbell_squat","type":"Exercise","label":"Barbell Squat","aliases":[]},
       {"id":"Exercise:kb_deadlift","type":"Exercise","label":"KB Deadlift","aliases":[]}
     ],
     "edges":[
       {"source":"Exercise:barbell_squat","predicate":"REQUIRES","target":"Equipment:barbell"},
       {"source":"Exercise:kb_deadlift","predicate":"VARIANT_OF","target":"ExerciseFamily:deadlift_family"}
     ],
     "safety_rules":[]}
    """
    private func engine() throws -> SafetyEngine {
        let a = try GraphArtifact.decode(from: Data(Self.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testMissingEquipmentWhenNotAvailable() throws {
        let r = try engine().equipmentReasons(exerciseID: "Exercise:barbell_squat",
                                              availableEquipment: ["Equipment:dumbbell"], constraints: [])
        XCTAssertEqual(r.map { $0.reasonCode }, ["MISSING_EQUIPMENT:barbell"])
        XCTAssertEqual(r[0].severity, "EQUIPMENT_HARD_BLOCK")
        XCTAssertEqual(r[0].graphPaths, ["Exercise:barbell_squat -REQUIRES-> Equipment:barbell"])
    }

    func testDisallowedEquipmentWhenNegatedConstraint() throws {
        let noBarbell = ResolvedConstraint(constraintType: "Equipment", value: "barbell",
                                           hard: true, sourceText: "no barbell", negated: true)
        let r = try engine().equipmentReasons(exerciseID: "Exercise:barbell_squat",
                                              availableEquipment: ["Equipment:barbell"], constraints: [noBarbell])
        XCTAssertEqual(r.map { $0.reasonCode }, ["DISALLOWED_EQUIPMENT:barbell"])
    }

    func testPromptExcludedFamily() throws {
        let exclude = ResolvedConstraint(constraintType: "ExerciseFamily", value: "deadlift_family",
                                         hard: true, sourceText: "exclude deadlifts", negated: true)
        let r = try engine().promptExclusionReasons(exerciseID: "Exercise:kb_deadlift", constraints: [exclude])
        XCTAssertEqual(r.map { $0.reasonCode }, ["PROMPT_EXCLUDED_FAMILY:deadlift_family"])
        XCTAssertEqual(r[0].severity, "PROMPT_EXCLUSION")
    }
}
