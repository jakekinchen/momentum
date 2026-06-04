import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class AppExerciseSessionViewModelTests: XCTestCase {
    func testDefaultViewModelDiscoversPackagedPresetResources() throws {
        let viewModel = AppExerciseSessionViewModel()

        viewModel.loadAvailablePresets()

        XCTAssertEqual(Set(viewModel.availablePresets.map(\.id)), [
            "bodyweight_lunge",
            "bodyweight_plank",
            "bodyweight_pushup",
            "bodyweight_squat"
        ])
        XCTAssertNotNil(viewModel.resolvedPresetSourceURL)
        XCTAssertTrue(viewModel.resolvedPresetSourceURL?.path.contains("Presets") == true)

        try viewModel.selectPreset(id: "bodyweight_plank")
        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_plank_clean_hold_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Plank")
        XCTAssertEqual(state.holdSeconds, 1.0, accuracy: 0.000_001)
        XCTAssertTrue(state.holdTargetReached)
        XCTAssertNotNil(state.presetSourceDescription)

        print(
            "app-viewmodel-default-resource source=\(viewModel.resolvedPresetSourceURL?.path ?? "nil") " +
            "presets=\(viewModel.availablePresets.map(\.id).joined(separator: ",")) held=\(state.holdSeconds) target=\(state.holdTargetReached)"
        )
    }

    func testLoadsBundledPresetListAndSelectsSquatAndPlank() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)

        viewModel.loadAvailablePresets()

        XCTAssertTrue(viewModel.availablePresets.contains { $0.id == "bodyweight_squat" && $0.kind == .reps })
        XCTAssertTrue(viewModel.availablePresets.contains { $0.id == "bodyweight_plank" && $0.kind == .hold })

        try viewModel.selectPreset(id: "bodyweight_squat")
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Squat")

        try viewModel.selectPreset(id: "bodyweight_plank")
        XCTAssertEqual(viewModel.state.selectedExerciseName, "Bodyweight Plank")

        print("app-viewmodel-presets \(viewModel.availablePresets.map { "\($0.id):\($0.kind.rawValue)" }.joined(separator: ","))")
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

    func testPlankFixtureUpdatesHoldProgressThroughAppSessionPath() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_plank")

        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_plank_clean_hold_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Plank")
        XCTAssertEqual(state.repCount, 0)
        XCTAssertEqual(state.holdSeconds, 1.0, accuracy: 0.000_001)
        XCTAssertTrue(state.holdTargetReached)
        XCTAssertNil(state.diagnosticText)

        print("app-viewmodel-plank fixture=synthetic_plank_clean_hold_trace held=\(state.holdSeconds) target=\(state.holdTargetReached) score=\(state.scoreText ?? "nil") diagnostic=\(state.diagnosticText ?? "nil")")
    }

    func testInvalidFixtureExposesDiagnosticWithoutClaimingSuccess() throws {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: Self.presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_plank")

        let state = try viewModel.process(frames: Self.loadPoseFixture("synthetic_plank_low_visibility_trace.json"))

        XCTAssertEqual(state.selectedExerciseName, "Bodyweight Plank")
        XCTAssertEqual(state.holdSeconds, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(state.holdTargetReached)
        XCTAssertNil(state.diagnosticText)

        let stateAtInvalidFrame = try Self.processPlankLowVisibilityThroughInvalidFrame()
        XCTAssertEqual(stateAtInvalidFrame.holdSeconds, 0)
        XCTAssertFalse(stateAtInvalidFrame.holdTargetReached)
        XCTAssertTrue(stateAtInvalidFrame.diagnosticText?.contains("low confidence landmark primary.hip") == true)

        print("app-viewmodel-invalid fixture=synthetic_plank_low_visibility_trace final_held=\(state.holdSeconds) final_target=\(state.holdTargetReached) invalid_diagnostic=\(stateAtInvalidFrame.diagnosticText ?? "nil")")
    }

    private static func processPlankLowVisibilityThroughInvalidFrame() throws -> AppExerciseSessionState {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: presetsDirectory)
        viewModel.loadAvailablePresets()
        try viewModel.selectPreset(id: "bodyweight_plank")
        let frames = Array(try loadPoseFixture("synthetic_plank_low_visibility_trace.json").prefix(3))
        return try viewModel.process(frames: frames)
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

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetsDirectory: URL {
        packageRoot.appendingPathComponent("Presets")
    }
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
