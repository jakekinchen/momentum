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

    func testOnlyDBAndKBPunctuationAndPromptShape() throws {
        let graph = try graph()
        let dbkb = try Resolver.resolveText("Only DB and KB.", graph: graph)
        XCTAssertEqual(dbkb.map { $0.constraintType }, ["Equipment", "Equipment"])
        XCTAssertEqual(Set(dbkb.map { $0.value }), ["dumbbell", "kettlebell"])
        XCTAssertTrue(dbkb.allSatisfy { $0.hard && $0.safetyBehavior == "allowed_equipment_only" })
        XCTAssertTrue(dbkb.allSatisfy { $0.confidence == 1.0 && $0.resolutionMethod == "exact" })

        let fullPrompt = try Resolver.resolveText(
            "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB.",
            graph: graph
        )
        XCTAssertEqual(
            fullPrompt.map { "\($0.constraintType):\($0.value)" },
            ["ExerciseFamily:deadlift_family", "Equipment:dumbbell", "Equipment:kettlebell"]
        )
        XCTAssertTrue(fullPrompt.dropFirst().allSatisfy { constraint in
            constraint.hard
                && constraint.safetyBehavior == "allowed_equipment_only"
                && constraint.confidence == 1.0
                && constraint.resolutionMethod == "exact"
        })
    }

    func testOnlyResistanceBandLoopAlias() throws {
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())
        let constraints = try Resolver.resolveText(
            "Build an arms routine. Only resistance band loop.",
            graph: graph
        )

        XCTAssertEqual(constraints.map { "\($0.constraintType):\($0.value)" }, ["Equipment:resistance_band_loop"])
        XCTAssertTrue(constraints.allSatisfy { $0.hard && $0.safetyBehavior == "allowed_equipment_only" })
        XCTAssertTrue(constraints.allSatisfy { $0.confidence == 0.92 && $0.resolutionMethod == "local_fuzzy_alias" })
    }

    func testUnknownTermIsUnresolvedHard() throws {
        let cs = try Resolver.resolveSingleClause("xyzzy", graph: try graph())
        XCTAssertEqual(cs[0].constraintType, "UnresolvedConcept")
        XCTAssertTrue(cs[0].hard)
        XCTAssertEqual(cs[0].resolutionStatus, "needs_review")
        XCTAssertEqual(cs[0].safetyBehavior, "ask_clarification")
        XCTAssertEqual(cs[0].confidence, 0.0)
        XCTAssertEqual(cs[0].resolutionMethod, "unresolved")
    }

    func testLocalFuzzyAliasesKeepSafetyCriticalSemantics() throws {
        let cases: [(String, String, String, Bool, Bool)] = [
            ("kne", "BodyRegion", "knee", false, false),
            ("no barbel", "Equipment", "barbell", true, true),
            ("dumbell", "Equipment", "dumbbell", false, false),
            ("kettle bell", "Equipment", "kettlebell", false, false),
            ("exclude dead lifts", "ExerciseFamily", "deadlift_family", true, true),
            ("low back", "BodyRegion", "lower_back", true, false),
            ("pectorals", "MuscleGroup", "chest", false, false),
        ]
        for (text, type, value, hard, negated) in cases {
            let cs = try Resolver.resolveSingleClause(text, graph: try graph())
            XCTAssertEqual(cs.count, 1, text)
            XCTAssertEqual(cs[0].constraintType, type, text)
            XCTAssertEqual(cs[0].value, value, text)
            XCTAssertEqual(cs[0].hard, hard, text)
            XCTAssertEqual(cs[0].negated, negated, text)
            XCTAssertEqual(cs[0].confidence, 0.92, text)
            XCTAssertEqual(cs[0].resolutionMethod, "local_fuzzy_alias", text)
        }
    }
}
