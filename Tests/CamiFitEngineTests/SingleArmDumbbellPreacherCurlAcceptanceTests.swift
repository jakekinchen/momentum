import XCTest
@testable import CamiFitEngine

final class SingleArmDumbbellPreacherCurlAcceptanceTests: XCTestCase {
    func testSingleArmDumbbellPreacherCurlPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "single_arm_dumbbell_preacher_curl")
        XCTAssertEqual(program.rep?.phaseSignal, "curl_elbow")

        try Self.assertAcceptance(
            name: "clean",
            program: program,
            frames: MotionDemoCompiler.compile(program: program).frames,
            expectedRepCount: 1
        )
        try Self.assertAcceptance(
            name: "shallow",
            program: program,
            frames: Self.shallowTrace(),
            expectedRepCount: 0
        )
    }

    func testVisuallyRejectedPreacherCurlTraceDoesNotShipPlayableMotionDemo() throws {
        let manifest = try Self.motionDemoManifest()
        let qaGates = try XCTUnwrap(manifest["qa_gates"] as? [String])

        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.motionDemoURL.path))
        XCTAssertEqual(manifest["acceptance_status"] as? String, "blocked_visual_rig_review_failed")
        XCTAssertEqual(manifest["playable_trace_packaged"] as? Bool, false)
        XCTAssertEqual(manifest["source_kind"] as? String, "licensed_external_reference_trace")
        XCTAssertEqual(manifest["source_license"] as? String, "Pixabay Content License")
        XCTAssertEqual(manifest["source_attribution"] as? String, "tixonov_valentin / Pixabay")
        XCTAssertEqual(
            manifest["source_page"] as? String,
            "https://pixabay.com/videos/crossfit-gym-workout-training-66991/"
        )
        XCTAssertTrue(qaGates.contains("source_timed_anatomical_retarget"))
        XCTAssertTrue(qaGates.contains("constant_forearm_length"))
        XCTAssertTrue((manifest["visual_review_failure"] as? String)?.contains("demoted") == true)
    }

    private static func assertAcceptance(
        name: String,
        program: ExerciseProgram,
        frames: [PoseFrame],
        expectedRepCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: frames)
        let formatted = EngineTraceFormatter.format(trace)
        let countedTimestamps = trace.filter(\.rep.countedThisFrame).map(\.timestampMS)
        let finalRepCount = trace.last?.rep.repCount ?? 0

        XCTAssertEqual(finalRepCount, expectedRepCount, name, file: file, line: line)
        XCTAssertEqual(countedTimestamps.count, expectedRepCount, name, file: file, line: line)
        XCTAssertTrue(formatted.contains("curl_elbow"), name, file: file, line: line)
        if name == "clean" {
            let selectedCues = trace.compactMap(\.formSummary.selectedCue)
            XCTAssertTrue(selectedCues.isEmpty, "\(name) produced form cues: \(selectedCues)", file: file, line: line)
        }

        print(
            [
                "single-arm-dumbbell-preacher-curl-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("single-arm-dumbbell-preacher-curl-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "curl_elbow"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.35, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        let primary: [String: PoseLandmark] = [
            "nose": point(0.495, 0.180, -0.03),
            "shoulder": point(0.500, 0.300, 0),
            "elbow": point(0.600, 0.540, 0.03),
            "wrist": point(mix(0.680, 0.460, factor), mix(0.760, 0.500, factor), 0.08),
            "hip": point(0.470, 0.590, 0),
            "knee": point(0.580, 0.720, 0.02),
            "ankle": point(0.630, 0.860, 0.05)
        ]
        var landmarks: [String: PoseLandmark] = [
            "nose": primary["nose"]!
        ]
        for (joint, value) in primary {
            landmarks["primary.\(joint)"] = value
            if joint != "nose" {
                landmarks["right.\(joint)"] = point(value.x, value.y, value.z + 0.10)
                landmarks["left.\(joint)"] = point(value.x - 0.09, value.y, value.z - 0.12)
            }
        }
        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static func point(_ x: Double, _ y: Double, _ z: Double) -> PoseLandmark {
        PoseLandmark(x: x, y: y, z: z, visibility: 1, presence: 1)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + ((b - a) * t)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/single_arm_dumbbell_preacher_curl.json")
    }

    private static var motionDemoURL: URL {
        packageRoot.appendingPathComponent(
            "Sources/CamiFitApp/Resources/MotionDemos/single_arm_dumbbell_preacher_curl.jsonl"
        )
    }

    private static var motionDemoManifestURL: URL {
        packageRoot.appendingPathComponent(
            "Sources/CamiFitApp/Resources/MotionDemos/single_arm_dumbbell_preacher_curl.manifest.json"
        )
    }

    private static func motionDemoManifest() throws -> [String: Any] {
        let data = try Data(contentsOf: motionDemoManifestURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func elbowAngle(in frame: PoseFrame) throws -> Double {
        let shoulder = try XCTUnwrap(frame.landmark(named: "primary.shoulder"))
        let elbow = try XCTUnwrap(frame.landmark(named: "primary.elbow"))
        let wrist = try XCTUnwrap(frame.landmark(named: "primary.wrist"))
        return angle(shoulder, elbow, wrist)
    }

    private static func angle(_ a: PoseLandmark, _ b: PoseLandmark, _ c: PoseLandmark) -> Double {
        let ab = (x: a.x - b.x, y: a.y - b.y)
        let cb = (x: c.x - b.x, y: c.y - b.y)
        let dot = (ab.x * cb.x) + (ab.y * cb.y)
        let magnitude = max(Self.distance(a, b) * Self.distance(c, b), 0.000_001)
        return acos(min(max(dot / magnitude, -1), 1)) * 180 / .pi
    }

    private static func distance(_ a: PoseLandmark, _ b: PoseLandmark) -> Double {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
