import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class AppExerciseSessionViewModelTests: XCTestCase {
    func testDefaultViewModelDiscoversPackagedPresetResources() throws {
        let viewModel = AppExerciseSessionViewModel()

        viewModel.loadAvailablePresets()

        XCTAssertTrue(Set([
            "bodyweight_lunge",
            "bodyweight_pushup",
            "bodyweight_squat",
            "single_arm_cable_tricep_extension"
        ]).isSubset(of: Set(viewModel.availablePresets.map(\.id))))
        XCTAssertNil(viewModel.availablePresets.first { $0.id == "bodyweight_pike" })
        XCTAssertEqual(viewModel.availablePresets.first { $0.id == "bodyweight_squat" }?.trackingReadiness, .guideReady)
        let availablePresetIDs = Set(viewModel.availablePresets.map(\.id))
        XCTAssertEqual(availablePresetIDs, AppExerciseTrackingGate.guideReadyPresetIDs)
        XCTAssertTrue(Set([
            "bodyweight_lunge",
            "bodyweight_pushup",
            "bodyweight_squat",
            "single_arm_cable_tricep_extension"
        ]).isSubset(of: availablePresetIDs))
        XCTAssertTrue(viewModel.availablePresets.allSatisfy { $0.trackingReadiness == .guideReady })
        for presetID in [
            "bench_lying_single_arm_dumbbell_tricep_extension",
            "bodyweight_jumping_jack",
            "bodyweight_pike",
            "bodyweight_plank",
            "machine_chest_supported_row",
            "resistance_band_reverse_curl",
            "single_arm_chest_supported_incline_row",
            "single_arm_dumbbell_preacher_curl",
            "suspension_tricep_press",
            "wide_grip_preacher_curl_with_ez_bar"
        ] {
            XCTAssertFalse(availablePresetIDs.contains(presetID), presetID)
            XCTAssertEqual(viewModel.trackingReadiness(forPresetID: presetID), .referenceCaptureRequired)
        }
        XCTAssertNotNil(viewModel.resolvedPresetSourceURL)
        XCTAssertTrue(viewModel.resolvedPresetSourceURL?.path.contains("Presets") == true)

        try viewModel.selectPreset(id: "bodyweight_pushup")
        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_pushup_clean_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Push-up")
        XCTAssertEqual(state.repCount, 1)
        XCTAssertNotNil(state.presetSourceDescription)

        print(
            "app-viewmodel-default-resource source=\(viewModel.resolvedPresetSourceURL?.path ?? "nil") " +
            "presets=\(viewModel.availablePresets.map(\.id).joined(separator: ",")) reps=\(state.repCount)"
        )
    }

    func testPackagedPresetCandidatesDoNotProbeLaunchCurrentDirectory() {
        let launchDirectory = URL(fileURLWithPath: "/Users/kelly/Documents")
        let candidates = AppExerciseSessionViewModel.defaultPresetSourceCandidates(
            bundleURL: URL(fileURLWithPath: "/Applications/Momentum.app", isDirectory: true),
            currentDirectory: launchDirectory
        )
        let candidatePaths = candidates.map(\.standardizedFileURL.path)

        XCTAssertFalse(candidatePaths.contains(launchDirectory.appendingPathComponent("Presets").path))
        XCTAssertFalse(candidatePaths.contains { $0.hasPrefix(launchDirectory.path) })
        XCTAssertTrue(candidatePaths.contains { $0.contains("/Library/Application Support/CamiFit/Presets") })

        print("app-viewmodel-packaged-preset-candidates=\(candidatePaths.joined(separator: ","))")
    }

    func testLoadsBundledPresetListAndSelectsGuideReadyPresetsOnly() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)

        viewModel.loadAvailablePresets()
        let availablePresetIDs = Set(viewModel.availablePresets.map(\.id))

        XCTAssertTrue(viewModel.availablePresets.contains { $0.id == "bodyweight_squat" && $0.kind == .reps })
        XCTAssertTrue(viewModel.availablePresets.contains {
            $0.id == "bodyweight_lunge"
                && $0.trackingReadiness == .guideReady
        })
        XCTAssertTrue(viewModel.availablePresets.contains {
            $0.id == "single_arm_cable_tricep_extension"
                && $0.trackingReadiness == .guideReady
        })
        XCTAssertEqual(availablePresetIDs, AppExerciseTrackingGate.guideReadyPresetIDs)

        try viewModel.selectPreset(id: "bodyweight_squat")
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Squat")

        try viewModel.selectPreset(id: "bodyweight_lunge")
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Lunge")

        try viewModel.selectPreset(id: "single_arm_cable_tricep_extension")
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Single-Arm Cable Tricep Extension")

        for presetID in [
            "bench_lying_single_arm_dumbbell_tricep_extension",
            "bodyweight_jumping_jack",
            "bodyweight_pike",
            "bodyweight_plank",
            "machine_chest_supported_row",
            "resistance_band_reverse_curl",
            "single_arm_chest_supported_incline_row",
            "single_arm_dumbbell_preacher_curl",
            "suspension_tricep_press",
            "wide_grip_preacher_curl_with_ez_bar"
        ] {
            XCTAssertFalse(viewModel.availablePresets.contains { $0.id == presetID }, presetID)
            XCTAssertThrowsError(try viewModel.selectPreset(id: presetID), presetID) { error in
                XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture(presetID))
            }
        }
    }

    func testReferenceCaptureGateMatchesPendingMotionProfiles() throws {
        let pendingProfileIDs = try Self.pendingReferenceCaptureProfileIDs()
        let bundledPresetIDs = try Self.presetIDs(in: Self.bundledPresetsDirectory)
        let pendingBundledPresetIDs = pendingProfileIDs.intersection(bundledPresetIDs)

        XCTAssertTrue(pendingBundledPresetIDs.isSubset(of: AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs))
        for presetID in AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs where bundledPresetIDs.contains(presetID) {
            XCTAssertTrue(pendingProfileIDs.contains(presetID), presetID)
        }

        for presetID in pendingProfileIDs {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: Self.motionDemosDirectory
                        .appendingPathComponent("\(presetID).jsonl")
                        .path
                ),
                presetID
            )
        }
    }

    func testInjectedMissingPresetDirectoryFailsClosed() {
        let missingDirectory = Self.packageRoot.appendingPathComponent("does-not-exist/presets")
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: missingDirectory)

        viewModel.loadAvailablePresets()

        XCTAssertEqual(viewModel.availablePresets, [])
        XCTAssertNil(viewModel.resolvedPresetSourceURL)
        XCTAssertEqual(viewModel.state.diagnosticText, "No presets found")

        print("app-viewmodel-missing-presets source=nil presets=0 diagnostic=\(viewModel.state.diagnosticText ?? "nil")")
    }

    func testSquatFixtureUpdatesRepCountThroughAppSessionPath() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_squat")

        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_squat_clean_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(state.repCount, 1)
        XCTAssertEqual(state.holdSeconds, 0)
        XCTAssertFalse(state.holdTargetReached)
        XCTAssertNil(state.diagnosticText)

        print("app-viewmodel-squat fixture=synthetic_squat_clean_trace reps=\(state.repCount) score=\(state.scoreText ?? "nil") diagnostic=\(state.diagnosticText ?? "nil")")
    }

    func testLiveFramePublishesRepFeedbackEventWhenRepCounts() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_squat")

        for frame in try Self.loadPoseFixture("synthetic_squat_clean_trace.json") {
            viewModel.ingestLiveFrame(frame)
        }

        let event = try XCTUnwrap(viewModel.lastFeedbackEvent)
        XCTAssertEqual(event.kind, .repCounted)
        XCTAssertEqual(event.emphasis, .clean)
        XCTAssertEqual(event.repsCompleted, 1)
        XCTAssertEqual(event.targetReps, 10)
        XCTAssertEqual(event.primaryText, "1")
        XCTAssertEqual(event.detailText, "1 / 10 reps")
        XCTAssertEqual(event.spokenText, "1")
    }

    func testVisualReviewDemotedPlankFailsClosedAtAppSessionBoundary() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()

        XCTAssertFalse(viewModel.availablePresets.contains { $0.id == "bodyweight_plank" })
        XCTAssertThrowsError(try viewModel.selectPreset(id: "bodyweight_plank")) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture("bodyweight_plank"))
        }
    }

    func testInvalidFixtureExposesDiagnosticWithoutClaimingSuccess() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_squat")

        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_squat_low_visibility_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Squat")
        XCTAssertEqual(state.repCount, 0)
        XCTAssertNil(state.diagnosticText)

        let invalidFrame = try Self.loadPoseFixture("synthetic_squat_low_visibility_trace.json")[2]
        let stateAtInvalidFrame = try viewModel.process(frames: [invalidFrame])
        XCTAssertEqual(stateAtInvalidFrame.repCount, 0)
        XCTAssertTrue(stateAtInvalidFrame.diagnosticText?.contains("low confidence landmark primary.knee") == true)

        print("app-viewmodel-invalid fixture=synthetic_squat_low_visibility_trace final_reps=\(state.repCount) invalid_diagnostic=\(stateAtInvalidFrame.diagnosticText ?? "nil")")
    }

    func testRoutineSessionMovesThroughGuideCountdownRestAndNextBlock() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        let routine = WorkoutRoutine(
            id: "test-routine",
            name: "Test Routine",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 1, restSeconds: 2),
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_pushup"), sets: 1, reps: 1)
            ]
        )

        try viewModel.startRoutine(routine)
        XCTAssertEqual(viewModel.routineSession.phase, .starting)
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 0)
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Squat")

        viewModel.beginRoutineGuide(seconds: 2)
        XCTAssertEqual(viewModel.routineSession.phase, .guide(secondsRemaining: 2))
        viewModel.tickRoutineGuide()
        XCTAssertEqual(viewModel.routineSession.phase, .guide(secondsRemaining: 1))
        viewModel.tickRoutineGuide()
        XCTAssertEqual(viewModel.routineSession.phase, .waitingForCamera)

        viewModel.beginRoutineCountdown(seconds: 2)
        viewModel.tickRoutineCountdown()
        XCTAssertEqual(viewModel.routineSession.phase, .countdown(secondsRemaining: 1))
        viewModel.tickRoutineCountdown()
        XCTAssertEqual(viewModel.routineSession.phase, .working)

        _ = try viewModel.process(frames: Self.loadPoseFixture("synthetic_squat_clean_trace.json"))
        XCTAssertEqual(viewModel.routineSession.phase, .resting(secondsRemaining: 2))
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 0)

        viewModel.tickRoutineRest()
        XCTAssertEqual(viewModel.routineSession.phase, .resting(secondsRemaining: 1))
        viewModel.tickRoutineRest()
        XCTAssertEqual(viewModel.routineSession.phase, .starting)
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 1)
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Push-up")
    }

    func testRoutineCanStartAtIndividualBlock() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()

        try viewModel.startRoutine(FutureRoutineCatalog.foundationRoutine, atBlock: 2)

        XCTAssertEqual(viewModel.routineSession.phase, .starting)
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 2)
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Lunge")
    }

    func testStartRoutineRejectsReferenceCapturePresetWithoutMutatingRoutineState() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        let initiallySelected = viewModel.state.selectedExerciseID
        let routine = WorkoutRoutine(
            id: "stale-pike",
            name: "Stale Pike",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_pike"), sets: 1, reps: 8)
            ]
        )

        XCTAssertThrowsError(try viewModel.startRoutine(routine)) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture("bodyweight_pike"))
        }
        XCTAssertNil(viewModel.activeRoutine)
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 0)
        XCTAssertEqual(viewModel.routineSession.phase, .idle)
        XCTAssertEqual(viewModel.state.selectedExerciseID, initiallySelected)
    }

    func testStartRoutineRejectsLaterReferenceCapturePresetWithoutMutatingRoutineState() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        let initiallySelected = viewModel.state.selectedExerciseID
        let routine = WorkoutRoutine(
            id: "mixed-stale-pike",
            name: "Mixed Stale Pike",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 10),
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_pike"), sets: 1, reps: 8)
            ]
        )

        XCTAssertThrowsError(try viewModel.startRoutine(routine)) { error in
            XCTAssertEqual(error as? AppExerciseSessionError, .presetRequiresReferenceCapture("bodyweight_pike"))
        }
        XCTAssertNil(viewModel.activeRoutine)
        XCTAssertEqual(viewModel.activeRoutineBlockIndex, 0)
        XCTAssertEqual(viewModel.routineSession.phase, .idle)
        XCTAssertEqual(viewModel.state.selectedExerciseID, initiallySelected)
    }

    func testRoutinePauseAndResumeRestoresPreviousPhase() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.startRoutine(FutureRoutineCatalog.foundationRoutine)

        viewModel.beginRoutineGuide(seconds: 6)
        viewModel.pauseRoutine()
        XCTAssertEqual(viewModel.routineSession.phase, .paused)

        viewModel.resumeRoutine()
        XCTAssertEqual(viewModel.routineSession.phase, .guide(secondsRemaining: 6))
    }

    private static func loadPoseFixture(_ name: String) throws -> [PoseFrame] {
        let url = packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/\(name)")
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(PoseFrameFixtureDTO.self, from: data)

        return fixture.frames.map { frame in
            PoseFrame(
                timestampMS: frame.timestampMS,
                imageWidth: fixture.imageWidth,
                imageHeight: fixture.imageHeight,
                landmarks: frame.landmarks.mapValues {
                    PoseLandmark(
                        x: $0.x,
                        y: $0.y,
                        z: $0.z,
                        visibility: $0.visibility,
                        presence: $0.presence
                    )
                }
            )
        }
    }

    private static func pendingReferenceCaptureProfileIDs() throws -> Set<String> {
        let url = packageRoot.appendingPathComponent("scripts/motion_reference/exercise_motion_profiles.json")
        let data = try Data(contentsOf: url)
        let registry = try JSONDecoder().decode(MotionProfileRegistryDTO.self, from: data)
        return Set(registry.profiles.compactMap { profile in
            profile.viewerStatus == "pending_reference_capture" ? profile.exerciseID : nil
        })
    }

    private static func presetIDs(in directory: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        var ids: Set<String> = []
        for url in urls where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            ids.insert(try JSONDecoder().decode(PresetIDDTO.self, from: data).id)
        }
        return ids
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

    private static var bundledPresetsDirectory: URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/Presets")
    }

    private static var motionDemosDirectory: URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos")
    }
}

private struct MotionProfileRegistryDTO: Decodable {
    let profiles: [MotionProfileDTO]
}

private struct MotionProfileDTO: Decodable {
    let exerciseID: String
    let viewerStatus: String

    private enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case viewerStatus = "viewer_status"
    }
}

private struct PresetIDDTO: Decodable {
    let id: String
}

private struct PoseFrameFixtureDTO: Decodable {
    let imageWidth: Double
    let imageHeight: Double
    let frames: [FrameDTO]

    private enum CodingKeys: String, CodingKey {
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case frames
    }
}

private struct FrameDTO: Decodable {
    let timestampMS: Int64
    let landmarks: [String: LandmarkDTO]

    private enum CodingKeys: String, CodingKey {
        case timestampMS = "timestamp_ms"
        case landmarks
    }
}

private struct LandmarkDTO: Decodable {
    let x: Double
    let y: Double
    let z: Double
    let visibility: Double
    let presence: Double
}
