import XCTest
@testable import CamiFitEngine

final class MediaPipePoseProviderTests: XCTestCase {
    func testDecodesPoseWorkerJSONLIntoNamedPoseFrames() throws {
        let provider = MediaPipePoseProvider(jsonlURL: Self.fixtureURL)

        let frames = try provider.frames()
        let first = try XCTUnwrap(frames.first)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.timestampMS), [1_000, 1_100])
        XCTAssertEqual(Set(frames.map(\.imageWidth)), [1_280])
        XCTAssertEqual(Set(frames.map(\.imageHeight)), [720])

        XCTAssertEqual(first.landmark(named: "right.shoulder"), PoseLandmark(x: 0.65, y: 0.24, z: -0.01, visibility: 0.98, presence: 0.99))
        XCTAssertEqual(first.landmark(named: "right.hip"), PoseLandmark(x: 0.65, y: 0.44, z: -0.01, visibility: 0.97, presence: 0.98))
        XCTAssertEqual(first.landmark(named: "right.knee"), PoseLandmark(x: 0.65, y: 0.64, z: -0.01, visibility: 0.96, presence: 0.97))
        XCTAssertEqual(first.landmark(named: "right.ankle"), PoseLandmark(x: 0.65, y: 0.84, z: -0.01, visibility: 0.95, presence: 0.96))
        XCTAssertEqual(first.landmark(named: "left.knee")?.visibility, 0.89)
        XCTAssertEqual(first.landmark(named: "left.knee")?.presence, 0.9)

        XCTAssertEqual(first.landmark(named: "primary.shoulder"), first.landmark(named: "right.shoulder"))
        XCTAssertEqual(first.landmark(named: "primary.hip"), first.landmark(named: "right.hip"))
        XCTAssertEqual(first.landmark(named: "primary.knee"), first.landmark(named: "right.knee"))
        XCTAssertEqual(first.landmark(named: "primary.ankle"), first.landmark(named: "right.ankle"))

        print("mediapipe-jsonl-decode frames=\(frames.count) timestamps=\(frames.map(\.timestampMS)) size=\(first.imageWidth)x\(first.imageHeight) primary_knee=\(String(describing: first.landmark(named: "primary.knee")))")
    }

    func testMissingPresenceDefaultsToVisibility() throws {
        let landmarks = Self.minimalLandmarksJSON(includePresence: false)
        let jsonl = """
        {"type":"pose","timestamp_ms":1200,"image_size":[640,480],"poses_detected":1,"primary_pose_id":0,"landmarks":\(landmarks),"world_landmarks":[]}
        """

        let frame = try XCTUnwrap(try MediaPipePoseJSONLDecoder.decode(jsonl: jsonl).first)

        XCTAssertEqual(frame.landmark(named: "right.knee")?.visibility, 0.96)
        XCTAssertEqual(frame.landmark(named: "right.knee")?.presence, 0.96)

        print("mediapipe-jsonl-presence-fallback right_knee_presence=\(frame.landmark(named: "right.knee")?.presence ?? -1)")
    }

    func testMalformedJSONLAndWrongLandmarkCountFailClosed() {
        XCTAssertThrowsError(try MediaPipePoseJSONLDecoder.decode(jsonl: #"{"type":"pose","timestamp_ms":1"#)) { error in
            XCTAssertTrue(String(describing: error).contains("malformed JSON"))
        }

        let jsonl = """
        {"type":"pose","timestamp_ms":1300,"image_size":[640,480],"poses_detected":1,"primary_pose_id":0,"landmarks":[],"world_landmarks":[]}
        """

        XCTAssertThrowsError(try MediaPipePoseJSONLDecoder.decode(jsonl: jsonl)) { error in
            XCTAssertTrue(String(describing: error).contains("expected 33 landmarks, got 0"))
        }

        print("mediapipe-jsonl-fail-closed malformed=true wrong_count=true")
    }

    func testNoPoseJSONLFramesPreserveTimelineAndProduceInvalidTraceEvidence() throws {
        let frames = try MediaPipePoseProvider(jsonlURL: Self.mixedNoPoseFixtureURL).frames()
        let noPoseFrame = try XCTUnwrap(frames.first { $0.timestampMS == 2_100 })
        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.presetURL))

        let trace = recorder.record(frames: frames)
        let formatted = EngineTraceFormatter.format(trace)
        let noPoseTrace = try XCTUnwrap(trace.first { $0.timestampMS == 2_100 })
        let countedInNoPoseInterval = trace.filter { $0.timestampMS == 2_100 && $0.rep.countedThisFrame }

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.timestampMS), [2_000, 2_100, 2_200])
        XCTAssertEqual(noPoseFrame.imageWidth, 1_280)
        XCTAssertEqual(noPoseFrame.imageHeight, 720)
        XCTAssertTrue(noPoseFrame.landmarks.isEmpty)
        XCTAssertTrue(countedInNoPoseInterval.isEmpty)
        XCTAssertEqual(trace.last?.rep.repCount, 0)
        XCTAssertNotNil(noPoseTrace.rep.invalidReason)
        XCTAssertTrue(formatted.contains("2100 | ready | 0 | false"))
        XCTAssertTrue(formatted.contains("missing landmark primary.hip"))

        print("mediapipe-jsonl-no-pose frames=\(frames.count) timestamps=\(frames.map(\.timestampMS)) no_pose=[\(noPoseFrame.timestampMS)] size=\(noPoseFrame.imageWidth)x\(noPoseFrame.imageHeight) counted_in_no_pose=\(countedInNoPoseInterval.count) final_reps=\(trace.last?.rep.repCount ?? -1)")
        print("mediapipe-jsonl-no-pose-trace\n\(Self.rowsContaining(formatted, "missing landmark"))")
    }

    func testInconsistentNoPoseRecordFailsClosed() {
        let jsonl = """
        {"type":"pose","timestamp_ms":1400,"image_size":[640,480],"poses_detected":0,"primary_pose_id":0,"landmarks":[],"world_landmarks":[]}
        """

        XCTAssertThrowsError(try MediaPipePoseJSONLDecoder.decode(jsonl: jsonl)) { error in
            XCTAssertTrue(String(describing: error).contains("no-pose record must have null primary_pose_id"))
        }

        print("mediapipe-jsonl-no-pose-inconsistent fail_closed=true")
    }

    func testDecodedFramesReachEngineTraceRecorderAndFormatter() throws {
        let frames = try MediaPipePoseProvider(jsonlURL: Self.fixtureURL).frames()
        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.presetURL))

        let trace = recorder.record(frames: frames)
        let formatted = EngineTraceFormatter.format(trace)

        XCTAssertEqual(trace.count, 2)
        XCTAssertTrue(formatted.contains("timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid"))
        XCTAssertTrue(formatted.contains("1000 |"))
        XCTAssertTrue(formatted.contains("knee=valid("))

        print("mediapipe-jsonl-trace frames=\(frames.count) trace=\(trace.count)\n\(formatted)")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var fixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_two_frames.jsonl")
    }

    private static var mixedNoPoseFixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/mediapipe_pose_worker_mixed_no_pose.jsonl")
    }

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func minimalLandmarksJSON(includePresence: Bool) -> String {
        (0 ..< MediaPipePoseJSONLDecoder.landmarkNames.count)
            .map { index in
                let values = landmarkValues(at: index)
                if includePresence {
                    return #"{"x":\#(values.x),"y":\#(values.y),"z":\#(values.z),"visibility":\#(values.visibility),"presence":\#(values.presence)}"#
                }
                return #"{"x":\#(values.x),"y":\#(values.y),"z":\#(values.z),"visibility":\#(values.visibility)}"#
            }
            .joined(separator: ",")
            .wrappedAsArray()
    }

    private static func landmarkValues(at index: Int) -> (x: Double, y: Double, z: Double, visibility: Double, presence: Double) {
        switch MediaPipePoseJSONLDecoder.landmarkNames[index] {
        case "right_shoulder":
            return (0.65, 0.24, -0.01, 0.98, 0.99)
        case "right_hip":
            return (0.65, 0.44, -0.01, 0.97, 0.98)
        case "right_knee":
            return (0.65, 0.64, -0.01, 0.96, 0.97)
        case "right_ankle":
            return (0.65, 0.84, -0.01, 0.95, 0.96)
        case "left_shoulder":
            return (0.35, 0.24, 0, 0.91, 0.92)
        case "left_hip":
            return (0.35, 0.44, 0, 0.9, 0.91)
        case "left_knee":
            return (0.35, 0.64, 0, 0.89, 0.9)
        case "left_ankle":
            return (0.35, 0.84, 0, 0.88, 0.89)
        default:
            return (0.5, 0.5, 0, 0.5, 0.5)
        }
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}

private extension String {
    func wrappedAsArray() -> String {
        "[\(self)]"
    }
}
