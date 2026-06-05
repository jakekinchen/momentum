import XCTest
@testable import CamiFitApp

final class ChatMarkdownRendererTests: XCTestCase {
    func testParsesStrongEmphasisForDynamicCoachText() {
        let rendered = ChatMarkdownRenderer.attributedString(for: "Try **Box squats** today.")

        XCTAssertEqual(String(rendered.characters), "Try Box squats today.")
        XCTAssertTrue(rendered.containsStrongEmphasis(on: "Box squats"))
    }

    func testPreservesLineBreaksAndListMarkersWhileStylingMarkdown() {
        let rendered = ChatMarkdownRenderer.attributedString(for: """
        Try a gentler option instead:
        - **Box squats** to a chair
        - **Glute bridges**
        """)

        XCTAssertEqual(String(rendered.characters), """
        Try a gentler option instead:
        - Box squats to a chair
        - Glute bridges
        """)
        XCTAssertTrue(rendered.containsStrongEmphasis(on: "Box squats"))
        XCTAssertTrue(rendered.containsStrongEmphasis(on: "Glute bridges"))
    }
}

private extension AttributedString {
    func containsStrongEmphasis(on text: String) -> Bool {
        runs.contains { run in
            String(self[run.range].characters) == text
                && (run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
        }
    }
}
