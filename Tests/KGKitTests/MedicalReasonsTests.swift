import XCTest
@testable import KGKit

final class MedicalReasonsTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let artifact = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: artifact), rules: artifact.safetyRules)
    }

    func testActiveKneeRestrictionBlocksLoadedDeepStress() throws {
        // Closure case: restriction is on the knee region; goblet_squat STRESSES the
        // left_knee sub-structure, so the PART_OF closure path is surfaced in graphPaths.
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "knee",
                                      hard: true, sourceText: "knee")
        let reasons = try engine().medicalReasons(exerciseID: "Exercise:goblet_squat", constraints: [knee])
        XCTAssertEqual(reasons.count, 1)
        XCTAssertEqual(reasons[0].severity, "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(reasons[0].reasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(reasons[0].graphPaths, [
            "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee",
            "BodyRegion:left_knee -PART_OF-> BodyRegion:knee",
            "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee",
        ])
    }

    func testNoRestrictionMeansNoMedicalReason() throws {
        let reasons = try engine().medicalReasons(exerciseID: "Exercise:goblet_squat", constraints: [])
        XCTAssertEqual(reasons.count, 0)
    }
}
