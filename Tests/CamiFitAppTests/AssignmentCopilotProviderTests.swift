import XCTest
@testable import CamiFitApp

final class AssignmentCopilotProviderTests: XCTestCase {
    func testRequiredQuickPromptsReturnGraphBackedFactCards() throws {
        let provider = AssignmentCopilotProvider()
        let prompts = [
            "Show me Jordan's morning brief",
            "What's the adherence trend?",
            "Sleep this week",
            "What changed since last week?",
            "What's the message pattern?",
            "What's the churn risk?",
        ]

        for prompt in prompts {
            let card = try provider.factCard(for: prompt)
            XCTAssertTrue(card.hasSupportingFact, prompt)
            XCTAssertFalse(card.summary.isEmpty, prompt)
            XCTAssertFalse(card.evidenceNodeIDs.isEmpty, prompt)
        }
    }

    func testChartPromptsExposeGraphDerivedSeries() throws {
        let provider = AssignmentCopilotProvider()
        let adherence = try provider.factCard(for: "adherence trend")
        let sleep = try provider.factCard(for: "sleep this week")

        XCTAssertGreaterThanOrEqual(adherence.chart.count, 2)
        XCTAssertGreaterThanOrEqual(sleep.chart.count, 7)
        XCTAssertTrue(adherence.chart.allSatisfy { $0.value >= 0 })
        XCTAssertTrue(sleep.chart.allSatisfy { $0.value > 0 })
    }

    func testMissingDataReturnsNoSupportingFactState() throws {
        let provider = AssignmentCopilotProvider(memberGraphData: {
            Data(#"{"nodes":[],"edges":[]}"#.utf8)
        })

        let card = try provider.factCard(for: "sleep this week")

        XCTAssertFalse(card.hasSupportingFact)
        XCTAssertEqual(card.title, "No supporting fact")
        XCTAssertTrue(card.evidenceNodeIDs.isEmpty)
    }

    func testFactRequestParserRequiresValidatedGraphLookupToolBlock() {
        let message = """
        I will check the member graph.

        ```future-kg-fact-request
        {"schemaVersion":1,"tool":"lookup_member_fact","query":"sleep","prompt":"Sleep this week","reason":"User asked for sleep"}
        ```

        ```future-kg-fact-request
        {"schemaVersion":1,"tool":"freehand_fact","query":"sleep"}
        ```
        """

        let requests = AssignmentCopilotRequestParser.parse(message: message)

        XCTAssertEqual(requests, [
            AssignmentCopilotRequest(
                query: .sleep,
                prompt: "Sleep this week",
                reason: "User asked for sleep"
            )
        ])
    }
}

@MainActor
final class ChatAssignmentCopilotRoutingTests: XCTestCase {
    func testCopilotPromptDoesNotBypassCoachWhenCodexIsUnavailable() {
        let chat = ChatViewModel()
        let provider = FakeAssignmentCopilotProvider()
        chat.assignmentCopilotProvider = provider

        chat.send("Sleep this week")

        XCTAssertTrue(provider.handledRequests.isEmpty)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertTrue(chat.messages[1].text.contains("Sign in to OpenAI"))
        XCTAssertTrue(chat.messages[1].copilotArtifacts.isEmpty)
        XCTAssertFalse(chat.isResponding)
    }

    func testAssistantFactRequestRunsLocalProviderAfterCoachTurn() {
        let chat = ChatViewModel()
        let provider = FakeAssignmentCopilotProvider()
        chat.assignmentCopilotProvider = provider

        let assistant = """
        I will check the saved member facts.

        ```future-kg-fact-request
        {"schemaVersion":1,"tool":"lookup_member_fact","query":"sleep","prompt":"Sleep this week","reason":"User asked for sleep"}
        ```
        """

        chat.appendCompletedAssistantResponse(
            assistant,
            sourceUserText: "Sleep this week"
        )

        XCTAssertEqual(provider.handledRequests, [
            AssignmentCopilotRequest(
                query: .sleep,
                prompt: "Sleep this week",
                reason: "User asked for sleep"
            )
        ])
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].copilotArtifacts.count, 1)
        XCTAssertFalse(chat.messages[0].text.contains("future-kg-fact-request"))
        XCTAssertEqual(chat.messages[0].text, "I will check the saved member facts.")
    }
}

private final class FakeAssignmentCopilotProvider: AssignmentCopilotProviding {
    var handledRequests: [AssignmentCopilotRequest] = []

    func factCard(for prompt: String) throws -> AssignmentCopilotFactCard {
        try factCard(for: AssignmentCopilotRequest(query: .sleep, prompt: prompt))
    }

    func factCard(for request: AssignmentCopilotRequest) throws -> AssignmentCopilotFactCard {
        handledRequests.append(request)
        return AssignmentCopilotFactCard(
            id: "sleep",
            title: "Sleep this week",
            summary: "Average sleep is 7.0 hours.",
            evidenceNodeIDs: ["BiomarkerObservation:jordan_sleep_last_7_days"],
            chart: [AssignmentCopilotChartPoint(id: "day-1", label: "Day 1", value: 7)],
            hasSupportingFact: true
        )
    }
}
