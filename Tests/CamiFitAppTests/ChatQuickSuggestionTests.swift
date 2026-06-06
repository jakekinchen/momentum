import XCTest
@testable import CamiFitApp

@MainActor
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

    func testResetSessionClearsTranscriptAndDraft() {
        let chat = ChatViewModel()
        chat.draft = "half-written request"
        chat.appendCompletedAssistantResponse("Try a crisp warm-up first.", sourceUserText: "warm-up")

        chat.resetSession()

        XCTAssertEqual(chat.draft, "")
        XCTAssertTrue(chat.messages.isEmpty)

        print("chat-reset-session cleared_transcript=true cleared_draft=true")
    }
}
