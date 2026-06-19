import Foundation
import KGKit

struct AssessmentExerciseSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let sourceExerciseID: String?
    let trackingCoverage: ExerciseTrackingCoverage
    let equipmentNames: [String]
    let movementPatternNames: [String]
    let muscleGroupNames: [String]
    let bodyRegionNames: [String]
    let familyNames: [String]
    let supportsWeight: Bool
    let isReps: Bool
    let isDuration: Bool

    var statusText: String { trackingCoverage.status.displayText }

    var mappedPresetText: String {
        trackingCoverage.mappedPresetID ?? "None"
    }

    var modeText: String {
        var modes: [String] = []
        if isReps { modes.append("Reps") }
        if isDuration { modes.append("Duration") }
        if supportsWeight { modes.append("Weighted") }
        return modes.isEmpty ? "Unspecified" : modes.joined(separator: " + ")
    }
}

enum ExerciseTrackingStatus: String, Equatable {
    case guideReady = "guide_ready"
    case archetypeDemoOnly = "archetype_demo_only"
    case recommendOnly = "recommend_only"

    var displayText: String {
        switch self {
        case .guideReady:
            return "Guide ready"
        case .archetypeDemoOnly:
            return "Archetype demo"
        case .recommendOnly:
            return "Recommend only"
        }
    }

    var measurementSupportText: String {
        switch self {
        case .guideReady:
            return "Exact"
        case .archetypeDemoOnly:
            return "Archetype"
        case .recommendOnly:
            return "None"
        }
    }
}

struct ExerciseTrackingCoverage: Equatable {
    let status: ExerciseTrackingStatus
    let mappedPresetID: String?
    let mappingKind: String?
    let mappingSource: String?
    let reasons: [String]
}

enum AssignmentExerciseTrackingCoverage {
    static func coverage(forExerciseID exerciseID: String, in graph: LocalGraph) -> ExerciseTrackingCoverage {
        if let pending = referenceCaptureRequiredPreset(for: exerciseID) {
            return referenceCaptureRequired(
                presetID: pending.presetID,
                reasons: pending.reasons
            )
        }

        if let exact = exactPresetID(for: exerciseID) {
            return exactCoverage(
                presetID: exact,
                mappedPresetID: exact,
                mappingKind: "exact_id",
                mappingSource: "kg_id"
            )
        }

        guard let node = graph.nodes[exerciseID] else {
            return recommendOnly(reason: "missing_exercise_node")
        }

        if let explicit = explicitPresetID(node), !explicit.isEmpty {
            return exactCoverage(
                presetID: explicit,
                mappedPresetID: explicit,
                mappingKind: "exact_property",
                mappingSource: "node_property"
            )
        }

        let families = Set(graph.outgoing(exerciseID, predicate: "VARIANT_OF").map(\.target))
        let label = node.label.lowercased()
        if families.contains("ExerciseFamily:lunge_family") {
            return archetype(presetID: "bodyweight_lunge", source: "ExerciseFamily:lunge_family")
        }
        if families.contains("ExerciseFamily:squat_family") {
            return archetype(presetID: "bodyweight_squat", source: "ExerciseFamily:squat_family")
        }
        if families.contains("ExerciseFamily:press_family") || label.contains("push-up") {
            return archetype(
                presetID: "bodyweight_pushup",
                source: families.contains("ExerciseFamily:press_family") ? "ExerciseFamily:press_family" : "label_contains:push-up"
            )
        }
        if families.contains("ExerciseFamily:core_family") || label.contains("plank") {
            return archetype(
                presetID: "bodyweight_plank",
                source: families.contains("ExerciseFamily:core_family") ? "ExerciseFamily:core_family" : "label_contains:plank"
            )
        }

        return recommendOnly(reason: "no_app_preset_mapping")
    }

    private static func archetype(presetID: String, source: String) -> ExerciseTrackingCoverage {
        guard AppExerciseTrackingGate.guideReadyPresetIDs.contains(presetID) else {
            return recommendOnly(reasons: [
                "archetype_preset_not_guide_ready",
                "exact_kg_exercise_measurement_not_supported"
            ])
        }
        return ExerciseTrackingCoverage(
            status: .archetypeDemoOnly,
            mappedPresetID: presetID,
            mappingKind: "family_archetype",
            mappingSource: source,
            reasons: [
                "uses_packaged_preset_demo_as_archetype",
                "exact_kg_exercise_measurement_not_supported"
            ]
        )
    }

    private static func exactCoverage(
        presetID: String,
        mappedPresetID: String,
        mappingKind: String,
        mappingSource: String
    ) -> ExerciseTrackingCoverage {
        if AppExerciseTrackingGate.guideReadyPresetIDs.contains(presetID) {
            return ExerciseTrackingCoverage(
                status: .guideReady,
                mappedPresetID: mappedPresetID,
                mappingKind: mappingKind,
                mappingSource: mappingSource,
                reasons: []
            )
        }

        if AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs.contains(presetID) {
            return referenceCaptureRequired(presetID: presetID, reasons: [
                "reference_capture_required",
                "mapped_preset_not_guide_ready"
            ])
        }

        return recommendOnly(reasons: [
            "mapped_preset_not_guide_ready",
            "preset_not_in_app_tracking_gate"
        ])
    }

    private static func recommendOnly(reason: String) -> ExerciseTrackingCoverage {
        recommendOnly(reasons: [reason])
    }

    private static func recommendOnly(reasons: [String]) -> ExerciseTrackingCoverage {
        ExerciseTrackingCoverage(
            status: .recommendOnly,
            mappedPresetID: nil,
            mappingKind: nil,
            mappingSource: nil,
            reasons: reasons
        )
    }

    private static func referenceCaptureRequired(presetID: String, reasons: [String]) -> ExerciseTrackingCoverage {
        ExerciseTrackingCoverage(
            status: .recommendOnly,
            mappedPresetID: presetID,
            mappingKind: "exact_id",
            mappingSource: "kg_id",
            reasons: reasons
        )
    }

    private static func referenceCaptureRequiredPreset(for exerciseID: String) -> (presetID: String, reasons: [String])? {
        switch exerciseID {
        case "Exercise:jumping_jack":
            return syntheticReferenceCaptureRequired("bodyweight_jumping_jack")
        case "Exercise:standing_miniband_hip_flexion":
            return syntheticReferenceCaptureRequired("standing_miniband_hip_flexion")
        case "Exercise:resistance_band_reverse_curl":
            return syntheticReferenceCaptureRequired("resistance_band_reverse_curl")
        case "Exercise:bodyweight_pike":
            return visualRigReviewRequired("bodyweight_pike")
        case "Exercise:bodyweight_plank":
            return visualRigReviewRequired("bodyweight_plank")
        case "Exercise:bench_lying_single_arm_dumbbell_tricep_extension":
            return syntheticReferenceCaptureRequired("bench_lying_single_arm_dumbbell_tricep_extension")
        case "Exercise:single_arm_dumbbell_preacher_curl":
            return visualRigReviewRequired("single_arm_dumbbell_preacher_curl")
        case "Exercise:suspension_tricep_press":
            return visualRigReviewRequired("suspension_tricep_press")
        case "Exercise:wide_grip_preacher_curl_with_ez_bar":
            return syntheticReferenceCaptureRequired("wide_grip_preacher_curl_with_ez_bar")
        case "Exercise:single_arm_chest_supported_incline_row":
            return syntheticReferenceCaptureRequired("single_arm_chest_supported_incline_row")
        case "Exercise:machine_chest_supported_row":
            return licenseReviewRequired("machine_chest_supported_row")
        default:
            return nil
        }
    }

    private static func syntheticReferenceCaptureRequired(_ presetID: String) -> (presetID: String, reasons: [String]) {
        (
            presetID,
            [
                "pending_licensed_reference_clip",
                "synthetic_archetype_trace_not_guide_ready"
            ]
        )
    }

    private static func visualRigReviewRequired(_ presetID: String) -> (presetID: String, reasons: [String]) {
        (
            presetID,
            [
                "visual_rig_review_failed",
                "avatar_head_neck_attachment_failed",
                "source_extraction_candidate_only"
            ]
        )
    }

    private static func licenseReviewRequired(_ presetID: String) -> (presetID: String, reasons: [String]) {
        (
            presetID,
            [
                "pending_source_license_review",
                "external_commons_license_review_needed"
            ]
        )
    }

    private static func exactPresetID(for exerciseID: String) -> String? {
        switch exerciseID {
        case "Exercise:bodyweight_squat":
            return "bodyweight_squat"
        case "Exercise:bodyweight_lunge":
            return "bodyweight_lunge"
        case "Exercise:bodyweight_pushup":
            return "bodyweight_pushup"
        case "Exercise:bodyweight_plank":
            return "bodyweight_plank"
        case "Exercise:jumping_jack":
            return "bodyweight_jumping_jack"
        case "Exercise:standing_miniband_hip_flexion":
            return "standing_miniband_hip_flexion"
        case "Exercise:resistance_band_reverse_curl":
            return "resistance_band_reverse_curl"
        case "Exercise:bodyweight_pike":
            return "bodyweight_pike"
        case "Exercise:single_arm_dumbbell_preacher_curl":
            return "single_arm_dumbbell_preacher_curl"
        case "Exercise:bench_lying_single_arm_dumbbell_tricep_extension":
            return "bench_lying_single_arm_dumbbell_tricep_extension"
        case "Exercise:single_arm_cable_tricep_extension":
            return "single_arm_cable_tricep_extension"
        case "Exercise:suspension_tricep_press":
            return "suspension_tricep_press"
        case "Exercise:wide_grip_preacher_curl_with_ez_bar":
            return "wide_grip_preacher_curl_with_ez_bar"
        case "Exercise:single_arm_chest_supported_incline_row":
            return "single_arm_chest_supported_incline_row"
        case "Exercise:machine_chest_supported_row":
            return "machine_chest_supported_row"
        default:
            return nil
        }
    }

    private static func explicitPresetID(_ node: GraphNode) -> String? {
        for key in ["camifit_preset_id", "app_preset_id", "runtime_preset_id", "preset_id"] {
            if let value = node.stringProperty(key) {
                return value
            }
        }
        return nil
    }
}

enum AssignmentExerciseCatalog {
    static func loadAssessmentExercises() throws -> [AssessmentExerciseSummary] {
        let graph = try LocalGraph(artifact: ArtifactLoader.assessmentBundled())
        return graph.nodesByType("Exercise").map { node in
            AssessmentExerciseSummary(
                id: node.id,
                name: node.label,
                sourceExerciseID: node.stringProperty("source_exercise_id"),
                trackingCoverage: AssignmentExerciseTrackingCoverage.coverage(forExerciseID: node.id, in: graph),
                equipmentNames: labels(for: node.id, predicate: "REQUIRES", in: graph),
                movementPatternNames: labels(for: node.id, predicate: "HAS_PATTERN", in: graph),
                muscleGroupNames: labels(for: node.id, predicate: "TARGETS", in: graph),
                bodyRegionNames: labels(for: node.id, predicate: "STRESSES", in: graph),
                familyNames: labels(for: node.id, predicate: "VARIANT_OF", in: graph),
                supportsWeight: node.boolProperty("supports_weight") ?? false,
                isReps: node.boolProperty("is_reps") ?? false,
                isDuration: node.boolProperty("is_duration") ?? false
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func labels(for sourceID: String, predicate: String, in graph: LocalGraph) -> [String] {
        let labels = graph.outgoing(sourceID, predicate: predicate)
            .compactMap { graph.nodes[$0.target]?.label }
        return Array(Set(labels)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private extension GraphNode {
    func stringProperty(_ key: String) -> String? {
        guard case let .string(value)? = properties[key] else { return nil }
        return value
    }

    func boolProperty(_ key: String) -> Bool? {
        guard case let .bool(value)? = properties[key] else { return nil }
        return value
    }
}
