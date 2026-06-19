import XCTest
@testable import CamiFitEngine

final class BodyweightPikeAcceptanceTests: XCTestCase {
    func testBodyweightPikePresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "bodyweight_pike")
        XCTAssertEqual(program.rep?.phaseSignal, "pike_angle")

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
        XCTAssertTrue(formatted.contains("pike_angle"), name, file: file, line: line)
        if name == "clean" {
            let selectedCues = trace.compactMap(\.formSummary.selectedCue)
            XCTAssertTrue(selectedCues.isEmpty, "\(name) produced form cues: \(selectedCues)", file: file, line: line)
        }

        print(
            [
                "bodyweight-pike-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("bodyweight-pike-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "pike_angle"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.35, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        let primary: [String: PoseLandmark] = [
            "nose": point(mix(0.660, 0.650, factor), mix(0.390, 0.400, factor), -0.03),
            "shoulder": point(mix(0.560, 0.580, factor), mix(0.480, 0.500, factor), 0),
            "elbow": point(mix(0.620, 0.630, factor), mix(0.600, 0.590, factor), 0.03),
            "wrist": point(0.680, 0.680, 0.08),
            "hip": point(mix(0.380, 0.390, factor), mix(0.560, 0.300, factor), 0),
            "knee": point(mix(0.290, 0.300, factor), mix(0.610, 0.480, factor), 0.02),
            "ankle": point(0.200, 0.660, 0.04)
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
        packageRoot.appendingPathComponent("Presets/bodyweight_pike.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
