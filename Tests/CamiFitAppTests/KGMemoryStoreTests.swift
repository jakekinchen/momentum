import XCTest
import KGKit
@testable import CamiFitApp

final class KGMemoryStoreTests: XCTestCase {
    private func temporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KGMemoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func addLeftKneePainOperation(sha: String, revision: Int) -> GraphOperation {
        GraphOperation(
            operationID: "op-left-knee-pain",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-05T15:00:00Z",
            baseArtifactSHA256: sha,
            preconditionRevision: revision,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:user-left-knee-pain-chat"],
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "left_knee",
                sourceText: "left knee pain",
                hard: true,
                negated: false,
                reviewAfter: "2026-09-05"
            )
        )
    }

    func testInitialWorkspaceLoadProjectsEmptyMemoryState() throws {
        let directory = try temporaryAppSupportDirectory()
        let store = KGMemoryStore(applicationSupportDirectory: directory)

        store.load()

        XCTAssertEqual(store.state.phase, .empty)
        XCTAssertEqual(store.state.overlayRevision, 0)
        XCTAssertEqual(store.state.items, [])
        XCTAssertNotEqual(store.state.baseArtifactShortHash, "unknown")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("KnowledgeGraph/overlays/member/current.jsonl").path))

        print("kg-memory-load phase=\(store.state.phase) revision=\(store.state.overlayRevision) base=\(store.state.baseArtifactShortHash)")
    }

    func testAddMedicalConstraintProjectsActiveMemory() throws {
        let directory = try temporaryAppSupportDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: directory,
            baseArtifactData: try ArtifactLoader.bundledData()
        )
        let log = GraphOperationLog(url: workspace.memberOverlayURL)
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)
        XCTAssertEqual(try log.append(addLeftKneePainOperation(sha: workspace.baseArtifactSHA256, revision: 0), validator: validator), 1)

        let store = KGMemoryStore(applicationSupportDirectory: directory)
        store.load()

        XCTAssertEqual(store.state.phase, .loaded)
        XCTAssertEqual(store.state.overlayRevision, 1)
        XCTAssertEqual(store.state.items.count, 1)
        XCTAssertEqual(store.state.items[0].status, .active)
        XCTAssertEqual(store.state.items[0].category, .healthSafety)
        XCTAssertEqual(store.state.items[0].title, "Left Knee")
        XCTAssertEqual(store.state.items[0].sourceText, "left knee pain")
        XCTAssertEqual(store.state.items[0].actor, .user)
        XCTAssertEqual(store.state.items[0].reviewAfter, "2026-09-05")
        XCTAssertEqual(store.state.items[0].evidence, ["SourceSpan:user-left-knee-pain-chat"])

        print("kg-memory-active id=\(store.state.items[0].operationID) title=\(store.state.items[0].title)")
    }

    func testCorrectHealthMemoryAppendsRetractionAndProjectsCorrectedStateWithoutMutatingBase() throws {
        let directory = try temporaryAppSupportDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: directory,
            baseArtifactData: try ArtifactLoader.bundledData()
        )
        let baseBefore = try Data(contentsOf: workspace.baseArtifactURL)
        let log = GraphOperationLog(url: workspace.memberOverlayURL)
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)
        XCTAssertEqual(try log.append(addLeftKneePainOperation(sha: workspace.baseArtifactSHA256, revision: 0), validator: validator), 1)

        let store = KGMemoryStore(applicationSupportDirectory: directory)
        store.load()
        try store.correctHealthMemory(operationID: "op-left-knee-pain", reason: "My left knee pain is resolved.")

        XCTAssertEqual(store.state.phase, .loaded)
        XCTAssertEqual(store.state.overlayRevision, 2)
        XCTAssertEqual(store.state.items.count, 1)
        XCTAssertEqual(store.state.items[0].status, .corrected)
        XCTAssertEqual(store.state.items[0].reason, "My left knee pain is resolved.")
        XCTAssertNotNil(store.state.items[0].replacesOperationID)
        XCTAssertEqual(try Data(contentsOf: workspace.baseArtifactURL), baseBefore)

        let mergedView = try MergedGraphView(workspace: workspace)
        XCTAssertFalse(mergedView.activeResolvedConstraints.contains { $0.nodeID == "BodyRegion:left_knee" })

        print("kg-memory-corrected revision=\(store.state.overlayRevision) status=\(store.state.items[0].status)")
    }

    func testUnderlyingValidatorStillFailsClosedForStaleRevisionAndWrongBaseHash() throws {
        let directory = try temporaryAppSupportDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: directory,
            baseArtifactData: try ArtifactLoader.bundledData()
        )
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)

        XCTAssertThrowsError(try validator.validate(addLeftKneePainOperation(sha: "wrong", revision: 0), currentRevision: 0)) { error in
            XCTAssertEqual(error as? OverlayValidator.ValidationError,
                           .baseArtifactMismatch(expected: workspace.baseArtifactSHA256, actual: "wrong"))
        }

        XCTAssertThrowsError(try validator.validate(addLeftKneePainOperation(sha: workspace.baseArtifactSHA256, revision: 1), currentRevision: 0)) { error in
            XCTAssertEqual(error as? OverlayValidator.ValidationError,
                           .revisionMismatch(expected: 0, actual: 1))
        }

        print("kg-memory-validation fail_closed=stale_revision,base_hash")
    }
}

