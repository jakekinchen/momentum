import XCTest
@testable import CamiFitEngine

final class WideGripPreacherCurlWithEZBarAcceptanceTests: XCTestCase {
    func testWideGripPreacherCurlWithEZBarPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "wide_grip_preacher_curl_with_ez_bar")
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
                "wide-grip-preacher-curl-ez-bar-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("wide-grip-preacher-curl-ez-bar-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "curl_elbow"))")
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
        packageRoot.appendingPathComponent("Presets/wide_grip_preacher_curl_with_ez_bar.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
