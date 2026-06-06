import XCTest
@testable import CamiFitApp

final class ChatQuickSuggestionTests: XCTestCase {
    func testSuggestionPromptOverwritesDraftAndSubmitsImmediately() {
        let chat = ChatViewModel()
        chat.draft = "half-written request"

        chat.send("Make my bodyweight lower body routine")

        XCTAssertEqual(chat.draft, "")
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].text, "Make my bodyweight lower body routine")
        XCTAssertTrue(chat.messages[1].text.contains("coach isn't connected"))

        print("chat-quick-suggestion draft_cleared=true submitted=lower_body")
    }
}
