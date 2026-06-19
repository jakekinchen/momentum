import XCTest
@testable import CamiFitEngine

final class SuspensionTricepPressAcceptanceTests: XCTestCase {
    func testSuspensionTricepPressPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "suspension_tricep_press")
        XCTAssertEqual(program.rep?.phaseSignal, "elbow_angle")

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
        XCTAssertTrue(formatted.contains("elbow_angle"), name, file: file, line: line)
        if name == "clean" {
            let selectedCues = trace.compactMap(\.formSummary.selectedCue)
            XCTAssertTrue(selectedCues.isEmpty, "\(name) produced form cues: \(selectedCues)", file: file, line: line)
        }

        print(
            [
                "suspension-tricep-press-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("suspension-tricep-press-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "elbow_angle"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.30, 0.40, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        let primary: [String: PoseLandmark] = [
            "nose": point(0.370, 0.250, -0.03),
            "shoulder": point(0.420, 0.360, 0),
            "elbow": point(0.510, 0.460, 0.03),
            "wrist": point(mix(0.400, 0.620, factor), mix(0.490, 0.580, factor), 0.08),
            "hip": point(0.620, 0.580, 0),
            "knee": point(0.730, 0.700, 0.02),
            "ankle": point(0.840, 0.820, 0.05)
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
        if let ankle = primary["ankle"] {
            landmarks["primary.heel"] = point(ankle.x - 0.045, ankle.y + 0.012, ankle.z)
            landmarks["primary.foot.index"] = point(ankle.x + 0.105, ankle.y + 0.018, ankle.z + 0.01)
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
        packageRoot.appendingPathComponent("Presets/suspension_tricep_press.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
