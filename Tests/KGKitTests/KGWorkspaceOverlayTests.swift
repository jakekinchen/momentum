import XCTest
@testable import KGKit

final class KGWorkspaceOverlayTests: XCTestCase {
    private func temporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KGWorkspaceOverlayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func workspace() throws -> KGWorkspace {
        try KGWorkspace.prepare(
            applicationSupportDirectory: temporaryAppSupportDirectory(),
            baseArtifactData: Data(GraphArtifactDecodeTests.json.utf8)
        )
    }

    private func addKneePainOperation(sha: String, revision: Int) -> GraphOperation {
        GraphOperation(
            operationID: "op-knee-pain-2026-06-05",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-05T15:00:00Z",
            baseArtifactSHA256: sha,
            preconditionRevision: revision,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:user-knee-pain-chat"],
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "knee",
                sourceText: "knee pain",
                hard: true,
                negated: false,
                reviewAfter: "2026-09-05",
                note: "User reported knee pain; review later instead of treating as permanent."
            )
        )
    }

    func testWorkspaceCopiesBaseArtifactByContentHashAndCreatesOverlayFiles() throws {
        let workspace = try workspace()

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.baseArtifactURL.path))
        XCTAssertTrue(workspace.baseArtifactURL.lastPathComponent.hasSuffix(".kgart.json"))
        XCTAssertTrue(workspace.baseArtifactURL.lastPathComponent.hasPrefix(workspace.baseArtifactSHA256))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.memberOverlayURL.path))
        XCTAssertEqual(try workspace.loadBaseArtifact().nodes.count, 3)
    }

    func testAppendOnlyKneePainOverlayCanBeCorrectedWithoutMutatingBaseArtifact() throws {
        let workspace = try workspace()
        let baseDataBefore = try Data(contentsOf: workspace.baseArtifactURL)
        let log = GraphOperationLog(url: workspace.memberOverlayURL)
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)

        XCTAssertEqual(try log.append(addKneePainOperation(sha: workspace.baseArtifactSHA256, revision: 0),
                                      validator: validator), 1)

        var view = try MergedGraphView(workspace: workspace)
        XCTAssertEqual(view.overlay.revision, 1)
        XCTAssertEqual(view.activeResolvedConstraints.map { $0.nodeID }, ["BodyRegion:knee"])

        var receipts = try SafetyEngine(graph: view.graph, rules: view.baseArtifact.safetyRules)
            .evaluateCandidates(["Exercise:goblet_squat"],
                                availableEquipment: ["Dumbbell"],
                                constraints: view.activeResolvedConstraints)
        XCTAssertEqual(receipts[0].decision, "filtered")
        XCTAssertEqual(receipts[0].primarySeverity, "MEDICAL_HARD_BLOCK")

        let resolved = GraphOperation(
            operationID: "op-knee-pain-resolved-2027-06-05",
            operationType: .retractMedicalConstraint,
            actor: .user,
            createdAt: "2027-06-05T15:00:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 1,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:user-knee-resolved-chat"],
            effect: GraphOperationEffect(
                replacesOperationID: "op-knee-pain-2026-06-05",
                reason: "Actually my knee pain is all better now."
            )
        )
        XCTAssertEqual(try log.append(resolved, validator: validator), 2)

        view = try MergedGraphView(workspace: workspace)
        XCTAssertEqual(view.overlay.revision, 2)
        XCTAssertEqual(view.activeResolvedConstraints, [])
        XCTAssertTrue(view.overlay.retractedOperationIDs.contains("op-knee-pain-2026-06-05"))

        receipts = try SafetyEngine(graph: view.graph, rules: view.baseArtifact.safetyRules)
            .evaluateCandidates(["Exercise:goblet_squat"],
                                availableEquipment: ["Dumbbell"],
                                constraints: view.activeResolvedConstraints)
        XCTAssertEqual(receipts[0].decision, "selected")
        XCTAssertEqual(try Data(contentsOf: workspace.baseArtifactURL), baseDataBefore)
    }

    func testOverlayValidationRejectsStaleRevisionBaseHashMismatchAndCanonicalMutation() throws {
        let workspace = try workspace()
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)

        XCTAssertThrowsError(try validator.validate(
            addKneePainOperation(sha: "wrong-sha", revision: 0),
            currentRevision: 0
        )) { error in
            XCTAssertEqual(error as? OverlayValidator.ValidationError,
                           .baseArtifactMismatch(expected: workspace.baseArtifactSHA256, actual: "wrong-sha"))
        }

        XCTAssertThrowsError(try validator.validate(
            addKneePainOperation(sha: workspace.baseArtifactSHA256, revision: 1),
            currentRevision: 0
        )) { error in
            XCTAssertEqual(error as? OverlayValidator.ValidationError,
                           .revisionMismatch(expected: 0, actual: 1))
        }

        let canonicalMutation = GraphOperation(
            operationID: "op-bad-canonical-mutation",
            operationType: .addPreference,
            actor: .agent,
            createdAt: "2026-06-05T15:10:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 0,
            scope: .member,
            effect: GraphOperationEffect(
                value: "try to edit canonical stress edge",
                mutationTarget: "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee"
            )
        )
        XCTAssertThrowsError(try validator.validate(canonicalMutation, currentRevision: 0)) { error in
            XCTAssertEqual(error as? OverlayValidator.ValidationError,
                           .canonicalMutationForbidden("Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee"))
        }
    }
}

