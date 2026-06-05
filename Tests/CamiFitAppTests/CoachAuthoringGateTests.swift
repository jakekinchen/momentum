import XCTest
@testable import CamiFitApp

final class CoachAuthoringGateTests: XCTestCase {
    /// Guard: free-LLM exercise authoring must stay OFF until a KG-backed ProgramCompiler is the
    /// author. The regimen parse/validate/save/card pipeline stays present-but-dormant on main;
    /// re-enabling authorship is a deliberate one-line flip, not an accident. See
    /// docs/design/2026-06-04-camifit-fitgraph-synthesis.md ("the graph decides; the LLM never
    /// decides eligibility").
    func testFreeLLMExerciseAuthoringDisabledByDefault() {
        XCTAssertFalse(
            CodexAppServerClient.exerciseAuthoringEnabled,
            "Coach must not freehand-author ExercisePrograms until the KG/compiler is the author."
        )
    }
}
