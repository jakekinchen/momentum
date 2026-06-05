import XCTest
@testable import KGKit

final class ModuleSmokeTests: XCTestCase {
    func testModuleVersionStampsArePresent() {
        XCTAssertEqual(KGVersion.graphVersion, "fitgraph-kg-m5-validation-v0")
        XCTAssertEqual(KGVersion.rulesetVersion, "ruleset-m2-safety-v0")
        XCTAssertEqual(KGVersion.ontologyLockVersion, "ontology-lock-m0-unverified")
    }
}
