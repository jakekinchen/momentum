import XCTest
@testable import KGKit

final class EvaluateCandidatesTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let a = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testFilteredKneeReceiptHasFingerprintAndStamps() throws {
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee",
                                      hard: true, sourceText: "left knee")
        let r = try engine().evaluateCandidates(["Exercise:goblet_squat"],
                                               availableEquipment: ["Dumbbell"], constraints: [knee])
        XCTAssertEqual(r.count, 1)
        let receipt = r[0]
        XCTAssertEqual(receipt.decision, "filtered")
        XCTAssertEqual(receipt.primarySeverity, "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(receipt.reasonCodes, ["ACTIVE_KNEE_RESTRICTION"])
        XCTAssertEqual(receipt.primaryReasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(receipt.graphVersion, KGVersion.graphVersion)
        XCTAssertEqual(receipt.constraintFingerprint.count, 16)
        // Fingerprint must equal the canonical computation for these exact inputs.
        XCTAssertEqual(receipt.constraintFingerprint,
            CanonicalJSON.fingerprint(availableEquipment: ["Equipment:dumbbell"],
                                      constraints: [knee], exerciseID: "Exercise:goblet_squat"))
    }

    func testSelectedReceiptWhenNoReasons() throws {
        let r = try engine().evaluateCandidates(["Exercise:goblet_squat"],
                                               availableEquipment: ["Dumbbell"], constraints: [])
        XCTAssertEqual(r[0].decision, "selected")
        XCTAssertEqual(r[0].primarySeverity, "BOOST")
        XCTAssertEqual(r[0].reasonCodes, ["PASSED_SAFETY"])
        XCTAssertEqual(r[0].graphPaths, [])
    }
}
