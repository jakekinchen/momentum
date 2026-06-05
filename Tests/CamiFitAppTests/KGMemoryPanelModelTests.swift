import XCTest
import KGKit
@testable import CamiFitApp

final class KGMemoryPanelModelTests: XCTestCase {
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
}
