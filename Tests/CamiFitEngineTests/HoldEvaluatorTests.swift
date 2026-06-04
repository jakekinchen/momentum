import XCTest
@testable import CamiFitEngine

final class HoldEvaluatorTests: XCTestCase {
    func testHoldTraceAccumulatesHeldSecondsAndReachesTargetThroughProductPath() throws {
        let frames = try Self.loadPoseFixture("synthetic_plank_hold_trace.json").frames
        var recorder = try EngineTraceRecorder(program: Self.holdProgram(targetSeconds: 1.0))

        let trace = recorder.record(frames: frames)
        let heldSeconds = trace.compactMap(\.hold?.heldSeconds)
        let targetReached = trace.compactMap(\.hold?.targetReached)
        let formatted = EngineTraceFormatter.format(trace)

        XCTAssertEqual(heldSeconds, [0.0, 0.5, 1.0, 1.5])
        XCTAssertEqual(targetReached, [false, false, true, true])
        XCTAssertTrue(trace.allSatisfy { $0.hold?.inRange == true })
        XCTAssertTrue(formatted.contains("hold"))
        XCTAssertTrue(formatted.contains("held=1.000,in_range=true,valid=true,target=true,reason=nil"))

        print("hold-product-path \(Self.formatHold(trace))")
        print("hold-product-path-format\n\(formatted)")
    }

    func testHoldEvaluatorResetsOnOutOfRangeFrames() throws {
        var recorder = try EngineTraceRecorder(program: Self.holdProgram(targetSeconds: 1.0))

        let trace = recorder.record(frames: [
            Self.plankFrame(timestampMS: 0),
            Self.plankFrame(timestampMS: 500),
            Self.sagFrame(timestampMS: 1_000),
            Self.plankFrame(timestampMS: 1_500)
        ])

        XCTAssertEqual(trace.compactMap(\.hold?.heldSeconds), [0.0, 0.5, 0.0, 0.0])
        XCTAssertEqual(trace[2].hold?.inRange, false)
        XCTAssertEqual(trace[2].hold?.valid, true)
        XCTAssertEqual(trace[2].hold?.notAccumulatingReason, "hold signal plank_line out of range")
        XCTAssertEqual(trace[3].hold?.inRange, true)
        XCTAssertEqual(trace[3].hold?.targetReached, false)

        print("hold-reset-out-of-range \(Self.formatHold(trace))")
    }

    func testHoldEvaluatorResetsOnInvalidSignalWithReason() throws {
        var recorder = try EngineTraceRecorder(program: Self.holdProgram(targetSeconds: 1.0))

        let trace = recorder.record(frames: [
            Self.plankFrame(timestampMS: 0),
            Self.plankFrame(timestampMS: 500),
            Self.lowVisibilityFrame(timestampMS: 1_000),
            Self.plankFrame(timestampMS: 1_500)
        ])

        XCTAssertEqual(trace.compactMap(\.hold?.heldSeconds), [0.0, 0.5, 0.0, 0.0])
        XCTAssertEqual(trace[2].hold?.inRange, false)
        XCTAssertEqual(trace[2].hold?.valid, false)
        XCTAssertTrue(trace[2].hold?.notAccumulatingReason?.contains("hold signal plank_line invalid") == true)
        XCTAssertTrue(trace[2].hold?.notAccumulatingReason?.contains("low confidence landmark primary.hip") == true)

        print("hold-reset-invalid \(Self.formatHold(trace))")
    }

    func testHoldEvaluatorClampsLargeTimestampGaps() throws {
        var recorder = try EngineTraceRecorder(program: Self.holdProgram(targetSeconds: 1.0))

        let trace = recorder.record(frames: [
            Self.plankFrame(timestampMS: 0),
            Self.plankFrame(timestampMS: 2_000)
        ])

        XCTAssertEqual(trace.compactMap(\.hold?.heldSeconds), [0.0, 0.5])
        XCTAssertEqual(trace.last?.hold?.targetReached, false)

        print("hold-clamp \(Self.formatHold(trace))")
    }

    private static func holdProgram(targetSeconds: Double) throws -> ExerciseProgram {
        let squat = try ProgramLoader.load(from: squatPresetURL)
        return ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: "test_plank_hold",
            name: "Test Plank Hold",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: [
                "plank_line_raw": "angle(primary.shoulder, primary.hip, primary.ankle)"
            ],
            filters: [
                "plank_line": SignalFilter(source: "plank_line_raw", type: .ema, alpha: 1, windowMS: nil)
            ],
            validity: squat.validity,
            rep: nil,
            hold: HoldConfig(signal: "plank_line", inRange: "plank_line >= 160", targetSeconds: targetSeconds),
            formRules: [],
            set: squat.set
        )
    }

    private static func loadPoseFixture(_ name: String) throws -> PoseFrameFixture {
        try PoseFrameFixtureLoader.load(from: fixtureURL(name))
    }

    private static func fixtureURL(_ name: String) -> URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/\(name)")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var squatPresetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func plankFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: plankLandmarks)
    }

    private static func sagFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: sagLandmarks)
    }

    private static func lowVisibilityFrame(timestampMS: Int64) -> PoseFrame {
        var landmarks = plankLandmarks
        landmarks["primary.hip"] = PoseLandmark(x: 0.5, y: 0.4, z: 0, visibility: 0.2, presence: 1)
        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static var plankLandmarks: [String: PoseLandmark] {
        landmarks(hipY: 0.4, hipVisibility: 1)
    }

    private static var sagLandmarks: [String: PoseLandmark] {
        landmarks(hipY: 0.58, hipVisibility: 1)
    }

    private static func landmarks(hipY: Double, hipVisibility: Double) -> [String: PoseLandmark] {
        [
            "left.shoulder": PoseLandmark(x: 0.3, y: 0.4, z: 0, visibility: 1, presence: 1),
            "left.hip": PoseLandmark(x: 0.5, y: hipY, z: 0, visibility: hipVisibility, presence: 1),
            "left.knee": PoseLandmark(x: 0.6, y: 0.4, z: 0, visibility: 1, presence: 1),
            "left.ankle": PoseLandmark(x: 0.7, y: 0.4, z: 0, visibility: 1, presence: 1),
            "right.shoulder": PoseLandmark(x: 0.3, y: 0.4, z: 0, visibility: 1, presence: 1),
            "right.hip": PoseLandmark(x: 0.5, y: hipY, z: 0, visibility: hipVisibility, presence: 1),
            "right.knee": PoseLandmark(x: 0.6, y: 0.4, z: 0, visibility: 1, presence: 1),
            "right.ankle": PoseLandmark(x: 0.7, y: 0.4, z: 0, visibility: 1, presence: 1),
            "primary.shoulder": PoseLandmark(x: 0.3, y: 0.4, z: 0, visibility: 1, presence: 1),
            "primary.hip": PoseLandmark(x: 0.5, y: hipY, z: 0, visibility: hipVisibility, presence: 1),
            "primary.knee": PoseLandmark(x: 0.6, y: 0.4, z: 0, visibility: 1, presence: 1),
            "primary.ankle": PoseLandmark(x: 0.7, y: 0.4, z: 0, visibility: 1, presence: 1)
        ]
    }

    private static func formatHold(_ trace: [EngineTraceFrame]) -> String {
        trace.map { frame in
            "\(frame.timestampMS):\(frame.hold?.description ?? "hold=nil")"
        }.joined(separator: " ")
    }
}
