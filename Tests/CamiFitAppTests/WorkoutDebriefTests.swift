import CamiFitEngine
import XCTest
@testable import CamiFitApp

@MainActor
final class WorkoutDebriefTests: XCTestCase {
    func testRoutineCompletionSummaryBuildsCoachDebriefPayload() throws {
        let summary = RoutineCompletionSummary(
            routineName: "One Squat",
            completedSets: 1,
            completedBlocks: 1,
            completedExerciseNames: ["Bodyweight Squat"],
            durationSeconds: 42,
            finalProgressText: "1 set complete",
            formSignals: ["Cue: Drive through the floor"],
            cameraIssues: []
        )

        let report = WorkoutCompletionReport(summary: summary)
        let prompt = WorkoutDebriefPrompt.makePrompt(for: report)

        XCTAssertEqual(report.scope, .routine)
        XCTAssertEqual(report.name, "One Squat")
        XCTAssertEqual(report.completedSets, 1)
        XCTAssertEqual(report.completedExercises, 1)
        XCTAssertEqual(report.durationSeconds, 42)
        XCTAssertTrue(prompt.contains("future-workout-result"))
        XCTAssertTrue(prompt.contains("\"artifactType\":\"workoutResult\""))
        XCTAssertTrue(prompt.contains("One Squat"))
        XCTAssertTrue(prompt.contains("Interpret this workout result like a coach"))
    }

    func testRunnerPublishesCompletionReportAfterRealSquatTrace() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(
            viewModel: viewModel,
            autoStartsTimers: false,
            now: {
                Self.clockTick += 1
                return Date(timeIntervalSince1970: Double(Self.clockTick))
            }
        )
        let routine = WorkoutRoutine(
            id: "one-squat",
            name: "One Squat",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 1, restSeconds: 0)
            ]
        )

        try runner.start(routine)
        runner.timerTick()
        runner.skipGuide()
        runner.updateCameraReadiness(.streaming(.zero))
        let frames = try Self.loadPoseFixture("synthetic_squat_clean_trace.json")
        runner.ingest(frames[0])
        runner.timerTick()
        runner.timerTick()
        runner.timerTick()
        for frame in frames {
            runner.ingest(frame)
        }

        guard let report = runner.lastCompletionReport else {
            return XCTFail("Expected a completion report")
        }
        XCTAssertEqual(report.name, "One Squat")
        XCTAssertEqual(report.completedSets, 1)
        XCTAssertEqual(report.completedExercises, 1)
        XCTAssertEqual(report.exerciseNames, ["Bodyweight Squat"])
        XCTAssertGreaterThanOrEqual(report.durationSeconds, 0)
    }

    func testStandaloneExerciseCompletionPublishesExerciseScopedReport() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(
            viewModel: viewModel,
            autoStartsTimers: false,
            now: {
                Self.clockTick += 1
                return Date(timeIntervalSince1970: Double(Self.clockTick))
            }
        )

        try runner.startExercise(exerciseID: "bodyweight_squat", mode: .camera, target: .reps(1))
        XCTAssertEqual(runner.runScope, .exercise)
        XCTAssertEqual(runner.phase, .preparing)

        runner.timerTick()
        runner.skipGuide()
        runner.updateCameraReadiness(.streaming(.zero))
        let frames = try Self.loadPoseFixture("synthetic_squat_clean_trace.json")
        runner.ingest(frames[0])
        runner.timerTick()
        runner.timerTick()
        runner.timerTick()
        for frame in frames {
            runner.ingest(frame)
        }

        guard let report = runner.lastCompletionReport else {
            return XCTFail("Expected standalone exercise report")
        }
        XCTAssertEqual(report.scope, .exercise)
        XCTAssertEqual(report.name, "Bodyweight Squat")
        XCTAssertEqual(report.completedSets, 1)
        XCTAssertEqual(report.completedExercises, 1)
        XCTAssertEqual(report.exerciseNames, ["Bodyweight Squat"])
    }

    func testGuideOnlyExerciseRunStaysInGuideAndDoesNotEmitAnalytics() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)

        try runner.startExercise(exerciseID: "bodyweight_squat", mode: .guide)
        XCTAssertEqual(runner.runScope, .exercise)
        XCTAssertEqual(runner.phase, .guide(secondsRemaining: 6))

        runner.timerTick()

        XCTAssertEqual(runner.phase, .guide(secondsRemaining: 6))
        XCTAssertNil(runner.lastCompletionReport)
    }

    func testGuideOnlyExerciseCanBePromotedToTrackedPractice() throws {
        let viewModel = Self.makeViewModel()
        let runner = RoutineRunner(viewModel: viewModel, autoStartsTimers: false)

        try runner.startExercise(exerciseID: "bodyweight_squat", mode: .guide, target: .reps(1))
        runner.startCurrentExercisePractice()

        XCTAssertFalse(runner.isGuideOnlyExerciseRun)
        XCTAssertEqual(runner.phase, .awaitingCamera(.idle))

        runner.updateCameraReadiness(.streaming(.zero))
        let frames = try Self.loadPoseFixture("synthetic_squat_clean_trace.json")
        runner.ingest(frames[0])
        runner.timerTick()
        runner.timerTick()
        runner.timerTick()
        for frame in frames {
            runner.ingest(frame)
        }

        XCTAssertEqual(runner.lastCompletionReport?.scope, .exercise)
        XCTAssertEqual(runner.lastCompletionReport?.name, "Bodyweight Squat")
    }

    private static var clockTick = 1_780_000_000

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
