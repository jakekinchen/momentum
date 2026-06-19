import XCTest
import CamiFitEngine
@testable import KGKit
@testable import CamiFitApp

final class AssignmentWorkoutPlannerTests: XCTestCase {
    func testPlannerGeneratesRoutineAndEvidenceFromAssessmentGraph() throws {
        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: temporaryDirectory())
        let artifact = try planner.makeArtifact(prompt: "Make me a 50-minute lower body workout")

        XCTAssertEqual(artifact.plan.timeWindowMinutes, 50)
        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:flat_bench"))
        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:resistance_band_loop"))
        XCTAssertFalse(artifact.selected.isEmpty)
        XCTAssertFalse(artifact.filtered.isEmpty)
        XCTAssertFalse(artifact.routine.blocks.isEmpty)
        XCTAssertTrue(artifact.presetMappings.allSatisfy {
            AppExerciseTrackingGate.guideReadyPresetIDs.contains($0.presetID)
        })
        XCTAssertTrue(artifact.filtered.contains { $0.reasonCodes.contains("ACTIVE_KNEE_RESTRICTION") })
        let injuryConstraint = try XCTUnwrap(artifact.plan.resolvedConstraints.first {
            $0.value == "left_knee"
                && $0.sourceText == "left knee active injury"
                && $0.safetyBehavior == "block_if_safety_critical"
        })
        XCTAssertEqual(injuryConstraint.laterality, "left")
        XCTAssertTrue(injuryConstraint.graphPaths.contains("BodyRegion:left_knee -PART_OF-> BodyRegion:knee"))
        XCTAssertTrue(artifact.selected.allSatisfy { !$0.primaryReasonCode.isEmpty })
        XCTAssertTrue(artifact.filtered.contains { !$0.graphPaths.isEmpty })

        if let guidedRoutine = artifact.routine.guidedOnly() {
            let executable = try Self.routineCompiler.compile(guidedRoutine)
            XCTAssertEqual(executable.blocks.count, artifact.routine.guidedBlocks.count)
            XCTAssertTrue(executable.blocks.allSatisfy { block in
                switch block.program.id {
                case "bodyweight_plank":
                    !block.target.isReps
                default:
                    true
                }
            })
        } else {
            XCTAssertTrue(artifact.routine.hasUnguidedBlocks)
        }
    }

    func testPlannerKeepsUnmappedSelectedExercisesVisibleAsRecommendations() throws {
        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: temporaryDirectory())
        let artifact = try planner.makeArtifact(prompt: "Build a 50-minute full body routine")
        let mappedExerciseIDs = Set(artifact.presetMappings.map(\.kgExerciseID))

        XCTAssertFalse(artifact.selected.isEmpty)
        XCTAssertFalse(artifact.recommendOnlySelected.isEmpty)
        XCTAssertTrue(artifact.recommendOnlySelected.allSatisfy { !mappedExerciseIDs.contains($0.exerciseID) })
        XCTAssertEqual(
            Set(Self.catalogExerciseIDs(artifact.routine.blocks)),
            Set(artifact.recommendOnlySelected.map(\.exerciseID))
        )
        XCTAssertTrue(artifact.routine.unguidedBlocks.allSatisfy {
            $0.guidance?.displayText.isEmpty == false && !$0.isGuideAvailable
        })
    }

    func testFullBodyRoutineEvidenceCoversEveryNonQuarantinedGoldenExercise() throws {
        let planner = AssignmentWorkoutPlanner(
            applicationSupportDirectory: temporaryDirectory(),
            availableEquipment: Self.allAssessmentEquipmentIDs()
        )
        let artifact = try planner.makeArtifact(prompt: "Build a 50-minute full body routine")
        let evidenceIDs = Set((artifact.selected + artifact.filtered).map(\.exerciseID))
        let expectedIDs = Set(Self.assessmentExerciseIDs())
            .subtracting(WorkoutGenerator.quarantinedExerciseIDs)

        XCTAssertEqual(expectedIDs.count, 49)
        XCTAssertEqual(evidenceIDs, expectedIDs)
        XCTAssertFalse(evidenceIDs.contains("Exercise:jumping_jack"))
        XCTAssertTrue(artifact.recommendOnlySelected.contains {
            $0.exerciseID == "Exercise:bench_lying_single_arm_dumbbell_tricep_extension"
        })
        XCTAssertTrue(
            AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs.isDisjoint(
                with: Set(Self.presetIDs(artifact.routine.blocks))
            )
        )
        XCTAssertTrue(
            AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs.isDisjoint(
                with: Set(artifact.presetMappings.map(\.presetID))
            )
        )
    }

    func testSyntheticReferenceCaptureRequiredExercisesStayRecommendationsOnly() throws {
        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: temporaryDirectory())
        let artifact = try planner.makeArtifact(prompt: "Build an arms tricep extension routine. only dumbbell and flat bench.")

        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:dumbbell"))
        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:flat_bench"))
        XCTAssertTrue(artifact.plan.selectedExercises.contains {
            $0.exerciseID == "Exercise:bench_lying_single_arm_dumbbell_tricep_extension"
        })
        XCTAssertTrue(artifact.recommendOnlySelected.contains {
            $0.exerciseID == "Exercise:bench_lying_single_arm_dumbbell_tricep_extension"
        })
        XCTAssertFalse(artifact.presetMappings.contains {
            $0.kgExerciseID == "Exercise:bench_lying_single_arm_dumbbell_tricep_extension"
        })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bench_lying_single_arm_dumbbell_tricep_extension"))
        XCTAssertTrue(Self.catalogExerciseIDs(artifact.routine.blocks).contains("Exercise:bench_lying_single_arm_dumbbell_tricep_extension"))
        XCTAssertTrue(artifact.routine.hasUnguidedBlocks)
    }

    func testArchetypeDemoOnlyExerciseStaysCatalogBlockNotRunnablePreset() throws {
        let planner = AssignmentWorkoutPlanner(
            applicationSupportDirectory: temporaryDirectory(),
            availableEquipment: Self.allAssessmentEquipmentIDs()
        )
        let artifact = try planner.makeArtifact(
            prompt: "Build a routine focused on Alternating Dumbbell Decline Bench Press."
        )

        XCTAssertTrue(artifact.plan.selectedExercises.contains {
            $0.exerciseID == "Exercise:alternating_dumbbell_decline_bench_press"
        })
        XCTAssertTrue(artifact.recommendOnlySelected.contains {
            $0.exerciseID == "Exercise:alternating_dumbbell_decline_bench_press"
        })
        XCTAssertFalse(artifact.presetMappings.contains {
            $0.kgExerciseID == "Exercise:alternating_dumbbell_decline_bench_press"
                || $0.presetID == "bodyweight_pushup"
        })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_pushup"))
        XCTAssertTrue(Self.catalogExerciseIDs(artifact.routine.blocks).contains(
            "Exercise:alternating_dumbbell_decline_bench_press"
        ))
    }

    func testRejectedJumpingJackStaysRecommendationOnlyAndDoesNotProjectRoutineBlock() throws {
        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: temporaryDirectory())
        let artifact = try planner.makeArtifact(prompt: "Build a routine focused on Jumping Jack. only bodyweight.")
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())
        let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: "Exercise:jumping_jack", in: graph)

        XCTAssertEqual(coverage.status, .recommendOnly)
        XCTAssertEqual(coverage.mappedPresetID, "bodyweight_jumping_jack")
        XCTAssertTrue(coverage.reasons.contains("pending_licensed_reference_clip"))
        XCTAssertTrue(artifact.selected.allSatisfy { $0.exerciseID != "Exercise:jumping_jack" })
        XCTAssertTrue(artifact.filtered.allSatisfy { $0.exerciseID != "Exercise:jumping_jack" })
        XCTAssertFalse(artifact.presetMappings.contains {
            $0.kgExerciseID == "Exercise:jumping_jack"
        })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_jumping_jack"))
    }

    func testVisualReviewDemotedPreacherCurlStaysRecommendationOnly() throws {
        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: temporaryDirectory())
        let artifact = try planner.makeArtifact(
            prompt: "Build an arms preacher curl routine. only dumbbell and preacher curl bench."
        )

        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:dumbbell"))
        XCTAssertTrue(artifact.plan.availableEquipment.contains("Equipment:preacher_curl_bench"))
        XCTAssertTrue(artifact.plan.selectedExercises.contains {
            $0.exerciseID == "Exercise:single_arm_dumbbell_preacher_curl"
        })
        XCTAssertTrue(artifact.recommendOnlySelected.contains {
            $0.exerciseID == "Exercise:single_arm_dumbbell_preacher_curl"
        })
        XCTAssertFalse(artifact.presetMappings.contains {
            $0.kgExerciseID == "Exercise:single_arm_dumbbell_preacher_curl"
                && $0.presetID == "single_arm_dumbbell_preacher_curl"
        })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("single_arm_dumbbell_preacher_curl"))
        XCTAssertTrue(Self.catalogExerciseIDs(artifact.routine.blocks).contains(
            "Exercise:single_arm_dumbbell_preacher_curl"
        ))
        XCTAssertTrue(artifact.routine.hasUnguidedBlocks)
    }

    func testPlannerIncludesLocalOverlayConstraints() throws {
        let appSupport = temporaryDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: appSupport,
            baseArtifactData: try ArtifactLoader.assessmentBundledData()
        )
        let operation = GraphOperation(
            operationID: "op-test-lower-back",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-06T00:00:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 0,
            scope: .member,
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "lower_back",
                sourceText: "bad lower back",
                hard: true,
                negated: false,
                reason: "test overlay"
            )
        )
        _ = try GraphOperationLog(url: workspace.memberOverlayURL)
            .append(operation, validator: OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256))

        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: appSupport)
        let artifact = try planner.makeArtifact(prompt: "Build a full body strength plan")

        XCTAssertEqual(artifact.overlayConstraintCount, 1)
        XCTAssertFalse(artifact.plan.resolvedConstraints.contains { $0.value == "left_knee" })
        XCTAssertTrue(artifact.plan.resolvedConstraints.contains { $0.value == "lower_back" })
        XCTAssertEqual(artifact.memoryReferences.map(\.operationID), ["op-test-lower-back"])
    }

    func testSavedWristMemoryKeepsLowerBodyRoutineSquatFirstAllowsGuideReadyLungeAndExcludesPlank() throws {
        let appSupport = temporaryDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: appSupport,
            baseArtifactData: try ArtifactLoader.assessmentBundledData()
        )
        let operation = GraphOperation(
            operationID: "op-test-wrist",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-06T00:00:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 0,
            scope: .member,
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "wrist",
                sourceText: "I'm having wrist pain.",
                hard: true,
                negated: false,
                reason: "avoid wrist-loading work"
            )
        )
        _ = try GraphOperationLog(url: workspace.memberOverlayURL)
            .append(operation, validator: OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256))

        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: appSupport)
        let artifact = try planner.makeArtifact(prompt: "Make a routine for lower body")

        XCTAssertFalse(artifact.routine.name.contains("KG"))
        XCTAssertEqual(artifact.memoryReferences.map(\.operationID), ["op-test-wrist"])
        XCTAssertTrue(artifact.plan.resolvedConstraints.contains { $0.value == "wrist" })
        XCTAssertFalse(artifact.plan.resolvedConstraints.contains { $0.value == "left_knee" })
        XCTAssertEqual(Self.presetIDs(artifact.routine.blocks).first, "bodyweight_squat")
        XCTAssertTrue(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_lunge"))
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_plank"))
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_pike"))
        XCTAssertTrue(artifact.presetMappings.contains { $0.presetID == "bodyweight_lunge" })
        XCTAssertFalse(artifact.presetMappings.contains { $0.presetID == "bodyweight_plank" })
        XCTAssertFalse(artifact.presetMappings.contains { $0.presetID == "bodyweight_pike" })
    }

    func testWristMemoryBlocksHandLoadedPikeRoutineProjection() throws {
        let appSupport = temporaryDirectory()
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: appSupport,
            baseArtifactData: try ArtifactLoader.assessmentBundledData()
        )
        let operation = GraphOperation(
            operationID: "op-test-wrist-pike",
            operationType: .addMedicalConstraint,
            actor: .user,
            createdAt: "2026-06-08T00:00:00Z",
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: 0,
            scope: .member,
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: "wrist",
                sourceText: "wrist pain",
                hard: true,
                negated: false,
                reason: "avoid hand-loaded work"
            )
        )
        _ = try GraphOperationLog(url: workspace.memberOverlayURL)
            .append(operation, validator: OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256))

        let planner = AssignmentWorkoutPlanner(applicationSupportDirectory: appSupport)
        let artifact = try planner.makeArtifact(prompt: "Build a core pike routine. only yoga mat.")

        XCTAssertTrue(artifact.plan.resolvedConstraints.contains { $0.value == "wrist" })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_pike"))
        XCTAssertFalse(artifact.presetMappings.contains { $0.presetID == "bodyweight_pike" })
    }

    func testReferenceCaptureRequiredPikePromptStaysCatalogRecommendationOnly() throws {
        let planner = AssignmentWorkoutPlanner(
            applicationSupportDirectory: temporaryDirectory(),
            availableEquipment: Self.allAssessmentEquipmentIDs()
        )
        let artifact = try planner.makeArtifact(prompt: "Build a core pike routine. only yoga mat.")

        XCTAssertTrue(artifact.plan.selectedExercises.contains {
            $0.exerciseID == "Exercise:bodyweight_pike"
        })
        XCTAssertTrue(artifact.recommendOnlySelected.contains {
            $0.exerciseID == "Exercise:bodyweight_pike"
        })
        XCTAssertFalse(artifact.presetMappings.contains {
            $0.kgExerciseID == "Exercise:bodyweight_pike"
                || $0.presetID == "bodyweight_pike"
        })
        XCTAssertFalse(Self.presetIDs(artifact.routine.blocks).contains("bodyweight_pike"))
        XCTAssertTrue(Self.catalogExerciseIDs(artifact.routine.blocks).contains("Exercise:bodyweight_pike"))
    }

    func testWorkoutRequestDetectorAndMinutes() {
        XCTAssertTrue(AssignmentWorkoutPlanner.isWorkoutRequest("Make my bodyweight lower body routine"))
        XCTAssertFalse(AssignmentWorkoutPlanner.isWorkoutRequest("How is my squat form?"))
        XCTAssertEqual(AssignmentWorkoutPlanner.minutes(in: "Build a 45-minute plan"), 45)
        XCTAssertEqual(AssignmentWorkoutPlanner.minutes(in: "Give me a 30 min workout"), 30)
    }

    func testWorkoutRequestParserRequiresValidatedPlannerToolBlock() {
        let message = """
        I will build that from your saved context.

        ```future-workout-plan
        {"schemaVersion":1,"tool":"generate_workout","prompt":"lower body bodyweight routine with bodyweight lunge first","minutes":45,"reason":"User asked for a routine"}
        ```

        ```future-workout-plan
        {"schemaVersion":1,"tool":"freehand_routine","prompt":"bad"}
        ```
        """

        let requests = KGWorkoutRequestParser.parse(message: message)

        XCTAssertEqual(requests, [
            KGWorkoutPlanningRequest(
                prompt: "lower body bodyweight routine with bodyweight lunge first",
                minutes: 45,
                reason: "User asked for a routine"
            )
        ])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static let routineCompiler = RoutineCompiler { presetID in
        try ProgramLoader.load(from: presetsDirectory.appendingPathComponent("\(presetID).json"))
    }

    private static func assessmentExerciseIDs() -> [String] {
        (try? LocalGraph(artifact: ArtifactLoader.assessmentBundled())
            .nodesByType("Exercise")
            .map(\.id)) ?? []
    }

    private static func allAssessmentEquipmentIDs() -> [String] {
        (try? LocalGraph(artifact: ArtifactLoader.assessmentBundled())
            .nodesByType("Equipment")
            .map(\.id)) ?? []
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetsDirectory: URL {
        packageRoot.appendingPathComponent("Presets")
    }

    private static func presetIDs(_ blocks: [RoutineBlock]) -> [String] {
        blocks.compactMap { block in
            if case let .preset(id) = block.exerciseRef {
                return id
            }
            return nil
        }
    }

    private static func catalogExerciseIDs(_ blocks: [RoutineBlock]) -> [String] {
        blocks.compactMap { block in
            if case let .catalog(id, _) = block.exerciseRef {
                return id
            }
            return nil
        }
    }
}

@MainActor
final class ChatKGWorkoutRoutingTests: XCTestCase {
    func testWorkoutPromptDoesNotBypassCoachWhenCodexIsUnavailable() {
        let chat = ChatViewModel()
        let planner = FakeAssignmentWorkoutPlanner()
        chat.assignmentWorkoutPlanner = planner

        chat.send("Make my bodyweight lower body routine")

        XCTAssertTrue(planner.handledRequests.isEmpty)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertTrue(chat.messages[1].text.contains("Sign in to OpenAI"))
        XCTAssertTrue(chat.messages[1].kgWorkoutArtifacts.isEmpty)
        XCTAssertTrue(chat.messages[1].regimen.isEmpty)
        XCTAssertFalse(chat.isResponding)
    }

    func testAssistantWorkoutPlanRequestRunsLocalPlannerAfterCoachTurn() {
        let chat = ChatViewModel()
        let planner = FakeAssignmentWorkoutPlanner()
        chat.assignmentWorkoutPlanner = planner

        let assistant = """
        I will build that as a lower-body routine.

        ```future-workout-plan
        {"schemaVersion":1,"tool":"generate_workout","prompt":"lower body bodyweight routine with bodyweight lunge first","minutes":50,"reason":"User asked for lower body"}
        ```
        """

        chat.appendCompletedAssistantResponse(
            assistant,
            sourceUserText: "Make my bodyweight lower body routine"
        )

        XCTAssertEqual(planner.handledRequests, [
            KGWorkoutPlanningRequest(
                prompt: "lower body bodyweight routine with bodyweight lunge first",
                minutes: 50,
                reason: "User asked for lower body"
            )
        ])
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].kgWorkoutArtifacts.count, 1)
        XCTAssertEqual(chat.messages[0].regimen.count, 1)
        XCTAssertFalse(chat.messages[0].text.contains("future-workout-plan"))
        XCTAssertEqual(chat.messages[0].text, "I will build that as a lower-body routine.")
    }
}

private final class FakeAssignmentWorkoutPlanner: AssignmentWorkoutPlanning {
    var handledRequests: [KGWorkoutPlanningRequest] = []

    func makeArtifact(prompt: String) throws -> KGWorkoutChatArtifact {
        try makeArtifact(request: KGWorkoutPlanningRequest(prompt: prompt))
    }

    func makeArtifact(request: KGWorkoutPlanningRequest) throws -> KGWorkoutChatArtifact {
        handledRequests.append(request)
        let routine = WorkoutRoutine(
            id: "kg-test",
            name: "Test Workout",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 8)
            ]
        )
        let plan = WorkoutPlan(
            memberID: "Member:jordan",
            prompt: request.prompt,
            timeWindowMinutes: request.minutes ?? 50,
            availableEquipment: ["Yoga Mat"],
            resolvedConstraints: [],
            unresolvedConcepts: [],
            warmup: [],
            main: [],
            cooldown: [],
            selectedExercises: [],
            filteredExercises: [],
            alternatives: []
        )
        return KGWorkoutChatArtifact(
            id: "kg-test",
            plan: plan,
            routine: routine,
            selected: [],
            filtered: [],
            alternatives: [],
            presetMappings: [],
            recommendOnlySelected: [],
            overlayConstraintCount: 0,
            memoryReferences: []
        )
    }
}
