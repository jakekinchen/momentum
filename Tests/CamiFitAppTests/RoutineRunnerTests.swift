import CamiFitEngine
import XCTest
@testable import CamiFitApp

@MainActor
final class RoutineRunnerTests: XCTestCase {
    func testRunnerMovesThroughGuidePoseCountdownWorkAndComplete() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)
        let routine = WorkoutRoutine(
            id: "one-squat",
            name: "One Squat",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 1, restSeconds: 0)
            ]
        )

        try runner.start(routine)
        XCTAssertEqual(runner.phase, .preparing)
        runner.timerTick()
        XCTAssertEqual(runner.phase, .guide(secondsRemaining: 6))
        runner.skipGuide()
        XCTAssertEqual(runner.phase, .awaitingCamera(.idle))
        runner.updateCameraReadiness(.streaming(.zero))
        XCTAssertEqual(runner.phase, .awaitingPose("Step into frame"))

        let frames = try Self.loadPoseFixture("synthetic_squat_clean_trace.json")
        runner.ingest(frames[0])
        XCTAssertEqual(runner.phase, .countdown(secondsRemaining: 3))
        runner.timerTick()
        runner.timerTick()
        runner.timerTick()
        XCTAssertEqual(runner.phase, .working)

        for frame in frames {
            runner.ingest(frame)
        }

        guard case let .complete(summary) = runner.phase else {
            return XCTFail("Expected complete, got \(runner.phase)")
        }
        XCTAssertEqual(summary.completedSets, 1)
        XCTAssertEqual(summary.routineName, "One Squat")
        XCTAssertEqual(runner.progressText, "1 set complete")
    }

    func testPauseFreezesRoutineProgressAndResumeRestoresPhase() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)
        try runner.start(Self.oneSquatRoutine)
        runner.timerTick()
        XCTAssertEqual(runner.phase, .guide(secondsRemaining: 6))

        runner.pause()
        XCTAssertEqual(runner.phase, .paused(previous: .guide(secondsRemaining: 6)))
        for frame in try Self.loadPoseFixture("synthetic_squat_clean_trace.json") {
            runner.ingest(frame)
        }
        XCTAssertEqual(viewModel.state.repCount, 0)

        runner.resume()
        XCTAssertEqual(runner.phase, .guide(secondsRemaining: 6))
    }

    func testThirtySecondRoutineHoldDoesNotCompleteAtPresetOneSecondTarget() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)
        let routine = WorkoutRoutine(
            id: "long-plank",
            name: "Long Plank",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 1, holdSeconds: 30, restSeconds: 0)
            ]
        )
        let frames = try Self.loadPoseFixture("synthetic_plank_clean_hold_trace.json")

        try runner.start(routine)
        runner.timerTick()
        runner.skipGuide()
        runner.updateCameraReadiness(.streaming(.zero))
        runner.ingest(frames[0])
        runner.timerTick()
        runner.timerTick()
        runner.timerTick()
        XCTAssertEqual(runner.phase, .working)

        for frame in frames {
            runner.ingest(frame)
        }

        XCTAssertEqual(runner.phase, .working)
        XCTAssertLessThan(viewModel.state.holdSeconds, 30)
        XCTAssertFalse(viewModel.state.holdTargetReached)
    }

    private static let oneSquatRoutine = WorkoutRoutine(
        id: "one-squat",
        name: "One Squat",
        blocks: [
            RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 1, restSeconds: 0)
        ]
    )

    private static func makeViewModel() -> AppExerciseSessionViewModel {
        let viewModel = AppExerciseSessionViewModel(presetsDirectory: presetsDirectory)
        viewModel.loadAvailablePresets()
        return viewModel
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

    struct FrameDTO: Decodable {
        let timestampMS: Int64
        let landmarks: [String: LandmarkDTO]

        private enum CodingKeys: String, CodingKey {
            case timestampMS = "timestamp_ms"
            case landmarks
        }
    }

    struct LandmarkDTO: Decodable {
        let x: Double
        let y: Double
        let z: Double
        let visibility: Double
        let presence: Double
    }
}
