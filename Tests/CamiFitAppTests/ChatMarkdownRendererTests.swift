import XCTest
@testable import CamiFitApp

final class ChatMarkdownRendererTests: XCTestCase {
    func testParsesStrongEmphasisForDynamicCoachText() {
        let rendered = ChatMarkdownRenderer.attributedString(for: "Try **Box squats** today.")

        XCTAssertEqual(String(rendered.characters), "Try Box squats today.")
        XCTAssertTrue(rendered.containsStrongEmphasis(on: "Box squats"))
    }

    func testParsesBlockMarkdownForChatRendering() {
        let blocks = ChatMarkdownRenderer.blocks(for: """
        Try a gentler option instead:
        ### Knee-friendly lower body routine
        - **Box squats** to a chair
        - **Glute bridges**
        1. **Side-lying leg raises**
        """)

        XCTAssertEqual(blocks, [
            ChatMarkdownBlock(kind: .paragraph, text: "Try a gentler option instead:"),
            ChatMarkdownBlock(kind: .heading(level: 3), text: "Knee-friendly lower body routine"),
            ChatMarkdownBlock(kind: .unorderedListItem, text: "**Box squats** to a chair"),
            ChatMarkdownBlock(kind: .unorderedListItem, text: "**Glute bridges**"),
            ChatMarkdownBlock(kind: .orderedListItem(number: "1"), text: "**Side-lying leg raises**")
        ])

        XCTAssertFalse(blocks[1].text.contains("###"))
        XCTAssertEqual(String(ChatMarkdownRenderer.attributedString(for: blocks[2].text).characters),
                       "Box squats to a chair")
        XCTAssertTrue(ChatMarkdownRenderer.attributedString(for: blocks[2].text).containsStrongEmphasis(on: "Box squats"))
        XCTAssertTrue(ChatMarkdownRenderer.attributedString(for: blocks[4].text).containsStrongEmphasis(on: "Side-lying leg raises"))
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
