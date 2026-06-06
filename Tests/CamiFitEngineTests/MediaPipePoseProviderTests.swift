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

    func testDecodesMotionDemoPoseJSONLWithExplicitSecondarySide() throws {
        let jsonl = """
        {"type":"motion_demo_pose","timestamp_ms":1500,"image_size":[1280,720],"landmarks":{"primary.shoulder":{"x":0.54,"y":0.43,"z":0,"visibility":1},"primary.hip":{"x":0.58,"y":0.66,"z":0,"visibility":1},"primary.knee":{"x":0.79,"y":0.67,"z":0.02,"visibility":1},"primary.ankle":{"x":0.80,"y":0.84,"z":0.05,"visibility":1},"secondary.shoulder":{"x":0.51,"y":0.43,"z":-0.18,"visibility":1,"presence":0.98},"secondary.hip":{"x":0.53,"y":0.665,"z":-0.18,"visibility":1},"secondary.knee":{"x":0.39,"y":0.76,"z":-0.16,"visibility":1},"secondary.ankle":{"x":0.30,"y":0.84,"z":-0.18,"visibility":1},"secondary.heel":{"x":0.255,"y":0.795,"z":-0.18,"visibility":1},"secondary.foot.index":{"x":0.37,"y":0.858,"z":-0.19,"visibility":1}}}
        """

        let frame = try XCTUnwrap(try MediaPipePoseJSONLDecoder.decode(jsonl: jsonl).first)

        XCTAssertEqual(frame.timestampMS, 1_500)
        XCTAssertEqual(frame.landmark(named: "secondary.shoulder")?.presence, 0.98)
        XCTAssertEqual(frame.landmark(named: "secondary.hip")?.presence, 1)
        XCTAssertEqual(frame.landmark(named: "secondary.foot.index")?.x, 0.37)

        print("motion-demo-pose-decode timestamp=\(frame.timestampMS) landmarks=\(frame.landmarks.keys.sorted().joined(separator: ","))")
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
        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.squatPresetURL))

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
        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.squatPresetURL))

        let trace = recorder.record(frames: frames)
        let formatted = EngineTraceFormatter.format(trace)

        XCTAssertEqual(trace.count, 2)
        XCTAssertTrue(formatted.contains("timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid"))
        XCTAssertTrue(formatted.contains("1000 |"))
        XCTAssertTrue(formatted.contains("knee=valid("))

        print("mediapipe-jsonl-trace frames=\(frames.count) trace=\(trace.count)\n\(formatted)")
    }

    func testBundledBodyweightLungeMotionDemoTraceDecodesAndCountsOneRep() throws {
        let frames = try MediaPipePoseProvider(jsonlURL: Self.bodyweightLungeMotionDemoURL).frames()
        let first = try XCTUnwrap(frames.first)
        let last = try XCTUnwrap(frames.last)
        let kneeAngles = frames.map(Self.kneeAngle(in:))
        let deepestIndex = try XCTUnwrap(kneeAngles.indices.min { kneeAngles[$0] < kneeAngles[$1] })
        let deepest = frames[deepestIndex]

        XCTAssertEqual(frames.count, 89)
        XCTAssertEqual(first.timestampMS, 0)
        XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $1.timestampMS > $0.timestampMS })
        for name in [
            "primary.shoulder",
            "primary.hip",
            "primary.knee",
            "primary.ankle",
            "secondary.shoulder",
            "secondary.hip",
            "secondary.knee",
            "secondary.ankle",
            "secondary.foot.index"
        ] {
            XCTAssertNotNil(first.landmark(named: name), name)
        }
        XCTAssertLessThan(Self.kneeAngle(in: deepest), 105)
        XCTAssertGreaterThan(Self.kneeAngle(in: first), 160)
        XCTAssertTrue(
            zip(kneeAngles[0...deepestIndex], kneeAngles[1...deepestIndex]).allSatisfy { next, current in
                current <= next + 0.000_001
            }
        )
        XCTAssertTrue(
            zip(kneeAngles[deepestIndex..<kneeAngles.endIndex], kneeAngles[(deepestIndex + 1)..<kneeAngles.endIndex]).allSatisfy { current, next in
                next >= current - 0.000_001
            }
        )

        let contactLandmarks = [
            "primary.heel",
            "primary.foot.index",
            "secondary.foot.index"
        ]
        let anchors = try Dictionary(uniqueKeysWithValues: contactLandmarks.map { name in
            (name, try XCTUnwrap(first.landmark(named: name), name))
        })
        for frame in frames {
            for name in contactLandmarks {
                let current = try XCTUnwrap(frame.landmark(named: name), name)
                let anchor = try XCTUnwrap(anchors[name], name)
                XCTAssertEqual(current.x, anchor.x, accuracy: 0.000_001, "\(name) x drifted at \(frame.timestampMS)ms")
                XCTAssertEqual(current.y, anchor.y, accuracy: 0.000_001, "\(name) y drifted at \(frame.timestampMS)ms")
            }
        }
        for name in [
            "nose",
            "primary.shoulder",
            "primary.hip",
            "primary.knee",
            "primary.ankle",
            "secondary.shoulder",
            "secondary.hip",
            "secondary.knee",
            "secondary.ankle"
        ] {
            let start = try XCTUnwrap(first.landmark(named: name), name)
            let end = try XCTUnwrap(last.landmark(named: name), name)
            XCTAssertEqual(start.x, end.x, accuracy: 0.000_001, "\(name) x loop boundary drifted")
            XCTAssertEqual(start.y, end.y, accuracy: 0.000_001, "\(name) y loop boundary drifted")
            XCTAssertEqual(start.z, end.z, accuracy: 0.000_001, "\(name) z loop boundary drifted")
        }

        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.lungePresetURL))
        let trace = recorder.record(frames: frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map(\.timestampMS)

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-resource-lunge frames=\(frames.count) " +
            "knee=\(Self.kneeAngle(in: deepest))..\(Self.kneeAngle(in: first)) " +
            "final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine() throws {
        enum Mode {
            case rep
            case hold
        }
        struct Case {
            let exerciseID: String
            let mode: Mode
            let contactLandmarks: [String]
            let requiredLandmarks: [String]
        }

        let cases = [
            Case(
                exerciseID: "bodyweight_squat",
                mode: .rep,
                contactLandmarks: ["primary.heel", "primary.foot.index", "secondary.heel", "secondary.foot.index"],
                requiredLandmarks: ["primary.shoulder", "primary.hip", "primary.knee", "primary.ankle"]
            ),
            Case(
                exerciseID: "bodyweight_pushup",
                mode: .rep,
                contactLandmarks: ["primary.wrist", "secondary.wrist", "primary.foot.index", "secondary.foot.index"],
                requiredLandmarks: ["primary.shoulder", "primary.elbow", "primary.wrist", "primary.hip", "primary.ankle"]
            ),
            Case(
                exerciseID: "bodyweight_plank",
                mode: .hold,
                contactLandmarks: ["primary.elbow", "secondary.elbow", "primary.foot.index", "secondary.foot.index"],
                requiredLandmarks: ["primary.shoulder", "primary.hip", "primary.ankle"]
            )
        ]

        for testCase in cases {
            let frames = try MediaPipePoseProvider(jsonlURL: Self.motionDemoURL(testCase.exerciseID)).frames()
            let first = try XCTUnwrap(frames.first, testCase.exerciseID)
            let last = try XCTUnwrap(frames.last, testCase.exerciseID)

            XCTAssertGreaterThan(frames.count, 2, testCase.exerciseID)
            XCTAssertEqual(first.timestampMS, 0, testCase.exerciseID)
            XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $1.timestampMS > $0.timestampMS }, testCase.exerciseID)

            for name in testCase.requiredLandmarks {
                XCTAssertNotNil(first.landmark(named: name), "\(testCase.exerciseID) missing \(name)")
                let start = try XCTUnwrap(first.landmark(named: name), "\(testCase.exerciseID) \(name)")
                let end = try XCTUnwrap(last.landmark(named: name), "\(testCase.exerciseID) \(name)")
                XCTAssertEqual(start.x, end.x, accuracy: 0.000_001, "\(testCase.exerciseID) \(name) x loop boundary drifted")
                XCTAssertEqual(start.y, end.y, accuracy: 0.000_001, "\(testCase.exerciseID) \(name) y loop boundary drifted")
                XCTAssertEqual(start.z, end.z, accuracy: 0.000_001, "\(testCase.exerciseID) \(name) z loop boundary drifted")
            }

            let anchors = try Dictionary(uniqueKeysWithValues: testCase.contactLandmarks.map { name in
                (name, try XCTUnwrap(first.landmark(named: name), "\(testCase.exerciseID) \(name)"))
            })
            for frame in frames {
                for name in testCase.contactLandmarks {
                    let current = try XCTUnwrap(frame.landmark(named: name), "\(testCase.exerciseID) \(name)")
                    let anchor = try XCTUnwrap(anchors[name], "\(testCase.exerciseID) \(name)")
                    XCTAssertEqual(current.x, anchor.x, accuracy: 0.000_001, "\(testCase.exerciseID) \(name) x drifted at \(frame.timestampMS)ms")
                    XCTAssertEqual(current.y, anchor.y, accuracy: 0.000_001, "\(testCase.exerciseID) \(name) y drifted at \(frame.timestampMS)ms")
                }
            }

            var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: Self.presetURL(testCase.exerciseID)))
            let trace = recorder.record(frames: frames)

            switch testCase.mode {
            case .rep:
                let counted = trace.filter { $0.rep.countedThisFrame }.map(\.timestampMS)
                XCTAssertEqual(trace.last?.rep.repCount, 1, testCase.exerciseID)
                XCTAssertEqual(counted.count, 1, testCase.exerciseID)
                print("motion-demo-resource-\(testCase.exerciseID) frames=\(frames.count) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)")
            case .hold:
                let targetReached = trace.compactMap { $0.hold?.targetReached == true ? $0.timestampMS : nil }
                XCTAssertGreaterThanOrEqual(targetReached.first ?? -1, 1_000, testCase.exerciseID)
                XCTAssertLessThanOrEqual(targetReached.first ?? Int64.max, 1_100, testCase.exerciseID)
                XCTAssertEqual(targetReached.last, frames.last?.timestampMS, testCase.exerciseID)
                XCTAssertGreaterThanOrEqual(trace.last?.hold?.heldSeconds ?? 0, 1.0, testCase.exerciseID)
                XCTAssertTrue(trace.allSatisfy { $0.hold?.inRange == true }, testCase.exerciseID)
                print("motion-demo-resource-\(testCase.exerciseID) frames=\(frames.count) target_reached=\(targetReached)")
            }
        }
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

    private static var squatPresetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func presetURL(_ exerciseID: String) -> URL {
        packageRoot.appendingPathComponent("Presets/\(exerciseID).json")
    }

    private static var lungePresetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_lunge.json")
    }

    private static var bodyweightLungeMotionDemoURL: URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl")
    }

    private static func motionDemoURL(_ exerciseID: String) -> URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos/\(exerciseID).jsonl")
    }

    private static func kneeAngle(in frame: PoseFrame) -> Double {
        guard let hip = frame.landmark(named: "primary.hip"),
              let knee = frame.landmark(named: "primary.knee"),
              let ankle = frame.landmark(named: "primary.ankle") else {
            return .infinity
        }

        let hipVector = (x: hip.x - knee.x, y: hip.y - knee.y)
        let ankleVector = (x: ankle.x - knee.x, y: ankle.y - knee.y)
        let dot = (hipVector.x * ankleVector.x) + (hipVector.y * ankleVector.y)
        let hipMagnitude = sqrt((hipVector.x * hipVector.x) + (hipVector.y * hipVector.y))
        let ankleMagnitude = sqrt((ankleVector.x * ankleVector.x) + (ankleVector.y * ankleVector.y))
        let cosine = min(max(dot / max(hipMagnitude * ankleMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
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
