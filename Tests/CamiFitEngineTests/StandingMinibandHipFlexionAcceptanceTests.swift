import XCTest
@testable import CamiFitEngine

final class StandingMinibandHipFlexionAcceptanceTests: XCTestCase {
    func testStandingMinibandHipFlexionPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "standing_miniband_hip_flexion")
        XCTAssertEqual(program.rep?.phaseSignal, "hip_flexion")

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
        XCTAssertTrue(formatted.contains("hip_flexion"), name, file: file, line: line)
        if name == "clean" {
            let selectedCues = trace.compactMap(\.formSummary.selectedCue)
            XCTAssertTrue(selectedCues.isEmpty, "\(name) produced form cues: \(selectedCues)", file: file, line: line)
        }

        print(
            [
                "standing-miniband-hip-flexion-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("standing-miniband-hip-flexion-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "hip_flexion"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.35, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        var landmarks: [String: PoseLandmark] = [
            "nose": point(mix(0.52, 0.51, factor), mix(0.17, 0.19, factor), -0.03),
            "primary.nose": point(mix(0.52, 0.51, factor), mix(0.17, 0.19, factor), -0.03),
            "primary.shoulder": point(mix(0.52, 0.51, factor), mix(0.29, 0.31, factor), 0),
            "primary.elbow": point(mix(0.49, 0.48, factor), mix(0.43, 0.44, factor), 0.03),
            "primary.wrist": point(mix(0.47, 0.46, factor), mix(0.55, 0.56, factor), 0.08),
            "primary.hip": point(0.52, 0.50, 0),
            "primary.knee": point(mix(0.52, 0.70, factor), mix(0.69, 0.54, factor), 0.02),
            "primary.ankle": point(mix(0.52, 0.73, factor), mix(0.86, 0.65, factor), 0.05),
            "right.shoulder": point(0.46, 0.30, -0.16),
            "right.elbow": point(0.43, 0.44, -0.16),
            "right.wrist": point(0.41, 0.56, -0.16),
            "right.hip": point(0.46, 0.50, -0.16),
            "right.knee": point(0.46, 0.68, -0.16),
            "right.ankle": point(0.46, 0.86, -0.16)
        ]
        for joint in ["shoulder", "elbow", "wrist", "hip", "knee", "ankle"] {
            landmarks["left.\(joint)"] = landmarks["primary.\(joint)"]
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
        packageRoot.appendingPathComponent("Presets/standing_miniband_hip_flexion.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
