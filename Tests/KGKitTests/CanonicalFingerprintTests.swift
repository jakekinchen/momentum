import XCTest
@testable import KGKit

final class CanonicalFingerprintTests: XCTestCase {
    func testAsciiCanonicalStringAndFingerprint() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true,
                                   sourceText: "left knee", negated: false)
        let canonical = CanonicalJSON.fingerprintPayload(
            availableEquipment: ["Equipment:dumbbell", "Equipment:kettlebell"],
            constraints: [c], exerciseID: "Exercise:goblet_squat")
        XCTAssertEqual(canonical,
          #"{"available_equipment":["Equipment:dumbbell","Equipment:kettlebell"],"constraints":[{"constraint_type":"BodyRegion","hard":true,"negated":false,"source_text":"left knee","value":"left_knee"}],"exercise_id":"Exercise:goblet_squat"}"#)
        XCTAssertEqual(CanonicalJSON.sha256Prefix16(canonical), "ccab5bbd240d730e")
    }

    func testEnsureAsciiAndUnescapedSlash() {
        let canonical = CanonicalJSON.fingerprintPayload(
            availableEquipment: [], constraints: [], exerciseID: "Exercise:café/squat")
        // ensure_ascii: output must contain no raw non-ASCII scalar, and '/' must
        // NOT be escaped. Asserted structurally + via the Python-pinned fingerprint,
        // so this file needs no hand-typed \uXXXX escape sequence.
        XCTAssertFalse(canonical.unicodeScalars.contains { $0.value > 0x7F },
                       "ensure_ascii: output must contain no raw non-ASCII scalars")
        XCTAssertTrue(canonical.contains("/"), "'/' must appear")
        XCTAssertFalse(canonical.contains("\\/"), "'/' must NOT be escaped")
        XCTAssertEqual(CanonicalJSON.sha256Prefix16(canonical), "77f08c176689bec5")
    }
}
