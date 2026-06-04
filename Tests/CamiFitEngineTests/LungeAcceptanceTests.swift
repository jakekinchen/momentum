import XCTest
@testable import CamiFitEngine

final class LungeAcceptanceTests: XCTestCase {
    func testBodyweightLungePresetLoadsAndAcceptanceFixturesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "bodyweight_lunge")

        let clean = try Self.loadPoseFixture("synthetic_lunge_clean_trace.json")
        let shallow = try Self.loadPoseFixture("synthetic_lunge_shallow_trace.json")

        try Self.assertAcceptance(
            name: "clean",
            program: program,
            frames: clean.frames,
            expectedRepCount: 1,
            expectedCountedTimestamps: [1_600],
            countedToleranceMS: 50
        )
        try Self.assertAcceptance(
            name: "shallow",
            program: program,
            frames: shallow.frames,
            expectedRepCount: 0,
            expectedCountedTimestamps: [],
            countedToleranceMS: 50
        )
    }

    private static func assertAcceptance(
        name: String,
        program: ExerciseProgram,
        frames: [PoseFrame],
        expectedRepCount: Int,
        expectedCountedTimestamps: [Int64],
        countedToleranceMS: Int64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: frames)
        let formatted = EngineTraceFormatter.format(trace)
        let countedTimestamps = trace.filter(\.rep.countedThisFrame).map(\.timestampMS)
        let finalRepCount = trace.last?.rep.repCount ?? 0

        XCTAssertEqual(finalRepCount, expectedRepCount, name, file: file, line: line)
        XCTAssertEqual(countedTimestamps.count, expectedCountedTimestamps.count, name, file: file, line: line)

        for (actual, expected) in zip(countedTimestamps, expectedCountedTimestamps) {
            XCTAssertLessThanOrEqual(
                abs(actual - expected),
                countedToleranceMS,
                "\(name) counted timestamp \(actual) not within \(countedToleranceMS)ms of \(expected)",
                file: file,
                line: line
            )
        }

        XCTAssertTrue(formatted.contains("timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid"))

        print(
            [
                "lunge-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "expected_counted=\(expectedCountedTimestamps)",
                "actual_counted=\(countedTimestamps)",
                "tolerance_ms=\(countedToleranceMS)"
            ].joined(separator: " ")
        )
        print("lunge-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, " | true | "))")
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

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_lunge.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
