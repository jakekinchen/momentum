import XCTest
@testable import KGKit

final class WorkoutOverlayBridgeTests: XCTestCase {
    private func temporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutOverlayBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func workspace() throws -> KGWorkspace {
        try KGWorkspace.prepare(
            applicationSupportDirectory: temporaryAppSupportDirectory(),
            baseArtifactData: try ArtifactLoader.bundledData()
        )
    }

    private func kneePainOperation(sha: String, revision: Int) -> GraphOperation {
        GraphOperation(
            operationID: "op-left-knee-pain-2026-06-05",
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

    func testWorkspaceOverlayConstraintsFeedWorkoutGeneratorAndCorrectionRerunsSafety() throws {
        let workspace = try workspace()
        let log = GraphOperationLog(url: workspace.memberOverlayURL)
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)
        let equipment = ["Equipment:dumbbell", "Equipment:kettlebell", "Equipment:yoga_mat"]

        XCTAssertEqual(try log.append(kneePainOperation(sha: workspace.baseArtifactSHA256, revision: 0),
                                      validator: validator), 1)

        let activePainPlan = try WorkoutGenerator.generateWorkout(
            workspace: workspace,
            prompt: "lower body",
            minutes: 50,
            availableEquipment: equipment
        )
        XCTAssertTrue(activePainPlan.resolvedConstraints.contains { $0.nodeID == "BodyRegion:left_knee" })
        XCTAssertTrue(activePainPlan.filteredExercises.contains { $0.exerciseID == "Exercise:goblet_squat" })
        XCTAssertFalse(activePainPlan.selectedExercises.contains { $0.exerciseID == "Exercise:goblet_squat" })

        let corrected = GraphOperation(
            operationID: "op-left-knee-pain-resolved-2027-06-05",
            operationType: .retractMedicalConstraint,
            actor: .user,
            createdAt: "2027-06-05T15:00:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 1,
            scope: .member,
            sourceSpanIDs: ["SourceSpan:user-left-knee-resolved-chat"],
            effect: GraphOperationEffect(
                replacesOperationID: "op-left-knee-pain-2026-06-05",
                reason: "Actually my knee pain is all better now."
            )
        )
        XCTAssertEqual(try log.append(corrected, validator: validator), 2)

        let correctedPlan = try WorkoutGenerator.generateWorkout(
            workspace: workspace,
            prompt: "lower body",
            minutes: 50,
            availableEquipment: equipment
        )
        XCTAssertFalse(correctedPlan.resolvedConstraints.contains { $0.nodeID == "BodyRegion:left_knee" })
        XCTAssertTrue(correctedPlan.selectedExercises.contains { $0.exerciseID == "Exercise:goblet_squat" })
        XCTAssertFalse(correctedPlan.filteredExercises.contains { $0.exerciseID == "Exercise:goblet_squat" })
    }
}

