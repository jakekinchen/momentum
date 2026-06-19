import XCTest
@testable import KGKit
@testable import CamiFitApp

final class AssignmentExerciseCatalogTests: XCTestCase {
    func testLoadsAllAssessmentExercisesForExerciseTab() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let statusCounts = Dictionary(grouping: exercises, by: { $0.trackingCoverage.status })
            .mapValues(\.count)

        XCTAssertEqual(exercises.count, 50)
        XCTAssertEqual(exercises.first?.name, "Alternating Dumbbell Decline Bench Press")
        XCTAssertEqual(statusCounts[.guideReady], 1)
        XCTAssertEqual(statusCounts[.archetypeDemoOnly], 14)
        XCTAssertEqual(statusCounts[.recommendOnly], 35)
    }

    func testAssessmentExerciseIncludesGraphMetadata() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let press = try XCTUnwrap(exercises.first {
            $0.id == "Exercise:alternating_dumbbell_decline_bench_press"
        })

        XCTAssertEqual(press.statusText, "Archetype demo")
        XCTAssertEqual(press.trackingCoverage.mappedPresetID, "bodyweight_pushup")
        XCTAssertTrue(press.trackingCoverage.reasons.contains("exact_kg_exercise_measurement_not_supported"))
        XCTAssertEqual(press.sourceExerciseID, "0fa0eb42-797f-4752-9a80-68e2dfb2a935")
        XCTAssertTrue(press.equipmentNames.contains("Dumbbell"))
        XCTAssertTrue(press.movementPatternNames.contains("upper push - horizontal"))
        XCTAssertTrue(press.muscleGroupNames.contains("chest"))
        XCTAssertTrue(press.familyNames.contains("Press Family"))
        XCTAssertTrue(press.supportsWeight)
        XCTAssertTrue(press.isReps)
        XCTAssertTrue(press.isDuration)
        XCTAssertEqual(press.modeText, "Reps + Duration + Weighted")
    }

    func testRejectedJumpingJackTraceRequiresReferenceClipBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let jumpingJack = try XCTUnwrap(exercises.first { $0.id == "Exercise:jumping_jack" })

        XCTAssertEqual(jumpingJack.statusText, "Recommend only")
        XCTAssertEqual(jumpingJack.trackingCoverage.mappedPresetID, "bodyweight_jumping_jack")
        XCTAssertEqual(jumpingJack.trackingCoverage.mappingKind, "exact_id")
        XCTAssertTrue(jumpingJack.trackingCoverage.reasons.contains("pending_licensed_reference_clip"))
        XCTAssertTrue(jumpingJack.trackingCoverage.reasons.contains("synthetic_archetype_trace_not_guide_ready"))
    }

    func testPikeTraceRequiresVisualRigReviewBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let pike = try XCTUnwrap(exercises.first { $0.id == "Exercise:bodyweight_pike" })

        XCTAssertEqual(pike.statusText, "Recommend only")
        XCTAssertEqual(pike.trackingCoverage.mappedPresetID, "bodyweight_pike")
        XCTAssertEqual(pike.trackingCoverage.mappingKind, "exact_id")
        XCTAssertTrue(pike.trackingCoverage.reasons.contains("visual_rig_review_failed"))
        XCTAssertTrue(pike.trackingCoverage.reasons.contains("avatar_head_neck_attachment_failed"))
        XCTAssertTrue(pike.trackingCoverage.reasons.contains("source_extraction_candidate_only"))
    }

    func testSuspensionTricepPressTraceRequiresVisualRigReviewBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let press = try XCTUnwrap(exercises.first { $0.id == "Exercise:suspension_tricep_press" })

        XCTAssertEqual(press.statusText, "Recommend only")
        XCTAssertEqual(press.trackingCoverage.mappedPresetID, "suspension_tricep_press")
        XCTAssertEqual(press.trackingCoverage.mappingKind, "exact_id")
        XCTAssertTrue(press.trackingCoverage.reasons.contains("visual_rig_review_failed"))
        XCTAssertTrue(press.trackingCoverage.reasons.contains("avatar_head_neck_attachment_failed"))
    }

    func testSingleArmDumbbellPreacherCurlTraceRequiresVisualRigReviewBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let curl = try XCTUnwrap(exercises.first { $0.id == "Exercise:single_arm_dumbbell_preacher_curl" })

        XCTAssertEqual(curl.statusText, "Recommend only")
        XCTAssertEqual(curl.trackingCoverage.mappedPresetID, "single_arm_dumbbell_preacher_curl")
        XCTAssertEqual(curl.trackingCoverage.mappingKind, "exact_id")
        XCTAssertTrue(curl.trackingCoverage.reasons.contains("visual_rig_review_failed"))
        XCTAssertTrue(curl.trackingCoverage.reasons.contains("avatar_head_neck_attachment_failed"))
    }

    func testMachineChestSupportedRowRequiresResolvedLicenseReviewBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let row = try XCTUnwrap(exercises.first { $0.id == "Exercise:machine_chest_supported_row" })

        XCTAssertEqual(row.statusText, "Recommend only")
        XCTAssertEqual(row.trackingCoverage.mappedPresetID, "machine_chest_supported_row")
        XCTAssertEqual(row.trackingCoverage.mappingKind, "exact_id")
        XCTAssertTrue(row.trackingCoverage.reasons.contains("pending_source_license_review"))
        XCTAssertTrue(row.trackingCoverage.reasons.contains("external_commons_license_review_needed"))
    }

    func testNewSyntheticExactMappingsRequireReferenceClipBeforeGuideReady() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let tricepExtension = try XCTUnwrap(exercises.first {
            $0.id == "Exercise:bench_lying_single_arm_dumbbell_tricep_extension"
        })
        let row = try XCTUnwrap(exercises.first {
            $0.id == "Exercise:single_arm_chest_supported_incline_row"
        })

        for exercise in [tricepExtension, row] {
            XCTAssertEqual(exercise.statusText, "Recommend only")
            XCTAssertEqual(exercise.trackingCoverage.mappingKind, "exact_id")
            XCTAssertTrue(exercise.trackingCoverage.reasons.contains("pending_licensed_reference_clip"))
            XCTAssertTrue(exercise.trackingCoverage.reasons.contains("synthetic_archetype_trace_not_guide_ready"))
        }
    }

    func testReferenceCaptureRequiredExactMappingsStayRecommendationOnly() throws {
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())
        let blockedMappings = [
            "Exercise:jumping_jack": "bodyweight_jumping_jack",
            "Exercise:bodyweight_plank": "bodyweight_plank",
            "Exercise:standing_miniband_hip_flexion": "standing_miniband_hip_flexion",
            "Exercise:resistance_band_reverse_curl": "resistance_band_reverse_curl",
            "Exercise:bodyweight_pike": "bodyweight_pike",
            "Exercise:single_arm_dumbbell_preacher_curl": "single_arm_dumbbell_preacher_curl",
            "Exercise:bench_lying_single_arm_dumbbell_tricep_extension": "bench_lying_single_arm_dumbbell_tricep_extension",
            "Exercise:suspension_tricep_press": "suspension_tricep_press",
            "Exercise:machine_chest_supported_row": "machine_chest_supported_row",
            "Exercise:wide_grip_preacher_curl_with_ez_bar": "wide_grip_preacher_curl_with_ez_bar",
            "Exercise:single_arm_chest_supported_incline_row": "single_arm_chest_supported_incline_row"
        ]

        XCTAssertEqual(Set(blockedMappings.values), AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs)
        for (exerciseID, presetID) in blockedMappings {
            let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: exerciseID, in: graph)

            XCTAssertEqual(coverage.status, .recommendOnly, exerciseID)
            XCTAssertEqual(coverage.mappedPresetID, presetID, exerciseID)
            XCTAssertEqual(coverage.mappingKind, "exact_id", exerciseID)
            XCTAssertTrue(coverage.reasons.contains { reason in
                reason == "pending_licensed_reference_clip"
                    || reason == "visual_rig_review_failed"
                    || reason == "pending_source_license_review"
            }, exerciseID)
        }
    }

    func testExactGuideReadyMappingsMatchAppGate() throws {
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())
        let guideReadyMappings = [
            "Exercise:bodyweight_squat": "bodyweight_squat",
            "Exercise:bodyweight_lunge": "bodyweight_lunge",
            "Exercise:bodyweight_pushup": "bodyweight_pushup",
            "Exercise:single_arm_cable_tricep_extension": "single_arm_cable_tricep_extension"
        ]

        XCTAssertEqual(Set(guideReadyMappings.values), AppExerciseTrackingGate.guideReadyPresetIDs)
        for (exerciseID, presetID) in guideReadyMappings {
            let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: exerciseID, in: graph)

            XCTAssertEqual(coverage.status, .guideReady, exerciseID)
            XCTAssertEqual(coverage.mappedPresetID, presetID, exerciseID)
            XCTAssertEqual(coverage.mappingKind, "exact_id", exerciseID)
            XCTAssertTrue(coverage.reasons.isEmpty, exerciseID)
        }
    }

    func testExplicitPresetPropertyCannotBypassAppTrackingGate() throws {
        let graph = try LocalGraph(artifact: GraphArtifact(
            graphVersion: "unit",
            rulesetVersion: "unit",
            ontologyLockVersion: "unit",
            nodes: [
                GraphNode(
                    id: "Exercise:unsafe_explicit",
                    type: "Exercise",
                    label: "Unsafe Explicit",
                    properties: ["camifit_preset_id": "bodyweight_pike"]
                )
            ],
            edges: [],
            safetyRules: []
        ))

        let coverage = AssignmentExerciseTrackingCoverage.coverage(
            forExerciseID: "Exercise:unsafe_explicit",
            in: graph
        )

        XCTAssertEqual(coverage.status, .recommendOnly)
        XCTAssertEqual(coverage.mappedPresetID, "bodyweight_pike")
        XCTAssertEqual(coverage.mappingKind, "exact_id")
        XCTAssertTrue(coverage.reasons.contains("reference_capture_required"))
        XCTAssertTrue(coverage.reasons.contains("mapped_preset_not_guide_ready"))
    }

    func testLicensedExternalLungeTraceRestoresLungeFamilyArchetypeDemo() throws {
        let exercises = try AssignmentExerciseCatalog.loadAssessmentExercises()
        let lunge = try XCTUnwrap(exercises.first { $0.id == "Exercise:barbell_racked_forward_lunge" })

        XCTAssertEqual(lunge.statusText, "Archetype demo")
        XCTAssertEqual(lunge.trackingCoverage.mappedPresetID, "bodyweight_lunge")
        XCTAssertEqual(lunge.trackingCoverage.mappingKind, "family_archetype")
        XCTAssertTrue(lunge.trackingCoverage.reasons.contains("uses_packaged_preset_demo_as_archetype"))
        XCTAssertTrue(lunge.trackingCoverage.reasons.contains("exact_kg_exercise_measurement_not_supported"))
    }

    func testFullBodyRoutineCandidatePoolExcludesQuarantinedJumpingJack() throws {
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())

        let candidates = WorkoutGenerator.candidateIds("Build a full body routine", graph)
        XCTAssertEqual(candidates.count, 49)
        XCTAssertFalse(candidates.contains("Exercise:jumping_jack"))
        XCTAssertEqual(WorkoutGenerator.candidateIds("Build a routine focused on Jumping Jack.", graph), [])
    }
}
