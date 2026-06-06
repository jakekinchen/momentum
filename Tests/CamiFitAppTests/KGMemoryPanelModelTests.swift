import XCTest
import KGKit
@testable import CamiFitApp

final class KGMemoryPanelModelTests: XCTestCase {
    private func temporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KGMemoryPanelModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testInspectorModeStatePreservesChatModelBoundary() {
        var state = AppInspectorState()

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.mode, .coach)
        XCTAssertTrue(state.isActive(.coach))

        state.toggleCoach()
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.mode, .coach)

        state.showMemory()
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.mode, .memory)
        XCTAssertTrue(state.isActive(.memory))

        state.toggleCoach()
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.mode, .coach)
        XCTAssertTrue(state.isActive(.coach))

        print("kg-memory-inspector-mode hidden_to_memory=true memory_to_coach=true state_is_value_only=true")
    }

    func testMemoryDisplayUsesUserFacingCopyAndDateFormatting() {
        XCTAssertEqual(KGMemoryDisplay.headerSubtitle, "Control what your coach remembers about you")
        XCTAssertEqual(KGMemoryDisplay.deleteReason, "Deleted from Memories panel.")

        let formatted = KGMemoryDisplay.formattedDate(
            "2026-06-05T15:00:00Z",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(formatted.replacingOccurrences(of: "\u{202F}", with: " "),
                       "Jun 5, 2026 at 3:00 PM")

        print("kg-memory-display subtitle=user_facing date=\(formatted)")
    }

    func testMedicalProjectionSeparatesActiveAndCorrectedRows() {
        let addKnee = GraphOperation(
            operationID: "op-knee",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-05T15:00:00Z",
            baseArtifactSHA256: "sha",
            preconditionRevision: 0,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:knee"],
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "knee",
                sourceText: "knee pain",
                hard: true
            )
        )
        let addShoulder = GraphOperation(
            operationID: "op-shoulder",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-06T15:00:00Z",
            baseArtifactSHA256: "sha",
            preconditionRevision: 1,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:shoulder"],
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "shoulder",
                sourceText: "shoulder pain",
                hard: true
            )
        )
        let retractKnee = GraphOperation(
            operationID: "op-knee-resolved",
            operationType: .retractMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-07T15:00:00Z",
            baseArtifactSHA256: "sha",
            preconditionRevision: 2,
            scope: .member,
            effect: GraphOperationEffect(
                replacesOperationID: "op-knee",
                reason: "resolved"
            )
        )

        let items = KGMemoryStore.projectMedicalMemories(from: [addKnee, addShoulder, retractKnee])

        XCTAssertEqual(items.map(\.operationID), ["op-shoulder", "op-knee"])
        XCTAssertEqual(items.map(\.status), [.active, .corrected])
        XCTAssertEqual(items[1].replacesOperationID, "op-knee-resolved")
        XCTAssertEqual(items[1].reason, "resolved")

        print("kg-memory-model active=\(items[0].operationID) corrected=\(items[1].operationID)")
    }

    func testCoachProposalParsesAndAppendsHealthMemoryArtifact() throws {
        let directory = try temporaryAppSupportDirectory()
        let store = KGMemoryStore(applicationSupportDirectory: directory)
        store.load()

        let assistantText = """
        I will remember that so future coaching avoids loading that area.

        ```future-kg-operation
        {
          "operation_type": "AddMedicalConstraint",
          "constraint_type": "BodyRegion",
          "value": "left_knee",
          "source_text": "I have left knee pain",
          "hard": true,
          "reason": "The user reported left knee pain, so knee-stressing workouts should be avoided."
        }
        ```
        """

        let artifacts = KGMemoryChatBridge.applyProposals(
            in: assistantText,
            sourceUserText: "I have left knee pain",
            store: store
        )

        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts[0].status, .saved)
        XCTAssertEqual(artifacts[0].title, "Memory saved")
        XCTAssertEqual(store.state.phase, .loaded)
        XCTAssertEqual(store.state.overlayRevision, 1)
        XCTAssertEqual(store.state.items.count, 1)
        XCTAssertEqual(store.state.items[0].title, "Left Knee")
        XCTAssertEqual(store.state.items[0].actor, .agent)
        XCTAssertEqual(store.state.items[0].sourceText, "I have left knee pain")

        let context = KGMemoryChatBridge.coachContext(from: store)
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("Left Knee") ?? false)
        XCTAssertTrue(context?.contains("I have left knee pain") ?? false)
        XCTAssertEqual(
            KGMemoryProposalParser.displayText(removingProposalBlocks: assistantText),
            "I will remember that so future coaching avoids loading that area."
        )

        print("kg-memory-chat-bridge artifact=saved title=\(store.state.items[0].title) context=true")
    }

    func testMalformedCoachProposalDoesNotAppendMemory() throws {
        let directory = try temporaryAppSupportDirectory()
        let store = KGMemoryStore(applicationSupportDirectory: directory)
        store.load()

        let assistantText = """
        ```future-kg-operation
        {"operation_type":"AddPreference","value":"likes squats"}
        ```
        """

        let artifacts = KGMemoryChatBridge.applyProposals(
            in: assistantText,
            sourceUserText: "I like squats",
            store: store
        )

        XCTAssertEqual(artifacts, [])
        XCTAssertEqual(store.state.phase, .empty)
        XCTAssertEqual(store.state.overlayRevision, 0)

        print("kg-memory-chat-bridge malformed_ignored=true revision=\(store.state.overlayRevision)")
    }
}
