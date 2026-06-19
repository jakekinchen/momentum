import XCTest
@testable import CamiFitEngine

final class SingleArmChestSupportedInclineRowAcceptanceTests: XCTestCase {
    func testSingleArmChestSupportedInclineRowPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "single_arm_chest_supported_incline_row")
        XCTAssertEqual(program.rep?.phaseSignal, "row_elbow")

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
        XCTAssertTrue(formatted.contains("row_elbow"), name, file: file, line: line)
        if name == "clean" {
            let selectedCues = trace.compactMap(\.formSummary.selectedCue)
            XCTAssertTrue(selectedCues.isEmpty, "\(name) produced form cues: \(selectedCues)", file: file, line: line)
        }

        print(
            [
                "single-arm-chest-supported-incline-row-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("single-arm-chest-supported-incline-row-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "row_elbow"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.35, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        let left: [String: PoseLandmark] = [
            "nose": point(0.430, 0.270, -0.03),
            "shoulder": point(0.460, 0.400, 0),
            "elbow": point(mix(0.550, 0.390, factor), mix(0.560, 0.500, factor), 0.03),
            "wrist": point(mix(0.660, 0.500, factor), mix(0.730, 0.550, factor), 0.08),
            "hip": point(0.580, 0.600, 0),
            "knee": point(0.720, 0.710, 0.02),
            "ankle": point(0.840, 0.830, 0.05)
        ]
        var landmarks: [String: PoseLandmark] = [
            "nose": left["nose"]!,
            "primary.nose": left["nose"]!
        ]
        for (joint, value) in left {
            landmarks["left.\(joint)"] = value
            landmarks["primary.\(joint)"] = value
            if joint != "nose" {
                landmarks["right.\(joint)"] = point(value.x + 0.09, value.y, value.z + 0.12)
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
        packageRoot.appendingPathComponent("Presets/single_arm_chest_supported_incline_row.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
