enum AppExerciseTrackingGate {
    static let guideReadyPresetIDs: Set<String> = [
        "bodyweight_lunge",
        "bodyweight_pushup",
        "bodyweight_squat",
        "single_arm_cable_tricep_extension"
    ]

    static let referenceCaptureRequiredPresetIDs: Set<String> = [
        "bench_lying_single_arm_dumbbell_tricep_extension",
        "bodyweight_jumping_jack",
        "bodyweight_pike",
        "bodyweight_plank",
        "machine_chest_supported_row",
        "resistance_band_reverse_curl",
        "single_arm_chest_supported_incline_row",
        "single_arm_dumbbell_preacher_curl",
        "standing_miniband_hip_flexion",
        "suspension_tricep_press",
        "wide_grip_preacher_curl_with_ez_bar"
    ]

    static func requiresReferenceCapture(_ presetID: String) -> Bool {
        referenceCaptureRequiredPresetIDs.contains(presetID)
    }
}
