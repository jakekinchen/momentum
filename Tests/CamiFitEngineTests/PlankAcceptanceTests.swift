import XCTest
@testable import CamiFitEngine

final class PlankAcceptanceTests: XCTestCase {
    func testBodyweightPlankPresetLoadsAndAcceptanceFixturesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "bodyweight_plank")
        XCTAssertNil(program.rep)
        XCTAssertNotNil(program.hold)

        try Self.assertAcceptance(
            AcceptanceCase(
                name: "clean",
                frames: Self.loadPoseFixture("synthetic_plank_clean_hold_trace.json").frames,
                expectedHeldSeconds: [0: 0.0, 500: 0.5, 1_000: 1.0],
                expectedTargetReachedTimestamps: [1_000],
                expectedResetTimestamps: [],
                expectedInvalidReasonExcerpt: nil
            ),
            program: program
        )
        try Self.assertAcceptance(
            AcceptanceCase(
                name: "broken",
                frames: Self.loadPoseFixture("synthetic_plank_broken_hold_trace.json").frames,
                expectedHeldSeconds: [0: 0.0, 500: 0.5, 1_000: 0.0, 1_500: 0.0, 2_000: 0.5],
                expectedTargetReachedTimestamps: [],
                expectedResetTimestamps: [1_000],
                expectedInvalidReasonExcerpt: "hold signal plank_line out of range"
            ),
            program: program
        )
        try Self.assertAcceptance(
            AcceptanceCase(
                name: "low_visibility",
                frames: Self.loadPoseFixture("synthetic_plank_low_visibility_trace.json").frames,
                expectedHeldSeconds: [0: 0.0, 500: 0.5, 1_000: 0.0, 1_500: 0.0, 2_000: 0.5],
                expectedTargetReachedTimestamps: [],
                expectedResetTimestamps: [1_000],
                expectedInvalidReasonExcerpt: "low confidence landmark primary.hip"
            ),
            program: program
        )
    }

    private static func assertAcceptance(
        _ acceptanceCase: AcceptanceCase,
        program: ExerciseProgram,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: acceptanceCase.frames)
        let formatted = EngineTraceFormatter.format(trace)
        let holdByTimestamp = Dictionary(uniqueKeysWithValues: trace.compactMap { frame -> (Int64, HoldSnapshot)? in
            guard let hold = frame.hold else {
                return nil
            }

            return (frame.timestampMS, hold)
        })
        let targetReachedTimestamps = trace.compactMap { frame in
            frame.hold?.targetReached == true ? frame.timestampMS : nil
        }
        let resetTimestamps: [Int64] = trace.compactMap { frame in
            guard let hold = frame.hold,
                  hold.heldSeconds == 0,
                  hold.notAccumulatingReason != nil else {
                return nil
            }

            return frame.timestampMS
        }

        XCTAssertEqual(holdByTimestamp.count, acceptanceCase.frames.count, acceptanceCase.name, file: file, line: line)
        XCTAssertEqual(targetReachedTimestamps, acceptanceCase.expectedTargetReachedTimestamps, acceptanceCase.name, file: file, line: line)
        XCTAssertEqual(resetTimestamps, acceptanceCase.expectedResetTimestamps, acceptanceCase.name, file: file, line: line)

        for (timestamp, expectedHeldSeconds) in acceptanceCase.expectedHeldSeconds {
            let hold = try XCTUnwrap(holdByTimestamp[timestamp], acceptanceCase.name, file: file, line: line)
            XCTAssertEqual(hold.heldSeconds, expectedHeldSeconds, accuracy: 0.000_001, acceptanceCase.name, file: file, line: line)
        }

        if let expectedInvalidReasonExcerpt = acceptanceCase.expectedInvalidReasonExcerpt {
            XCTAssertTrue(
                formatted.contains(expectedInvalidReasonExcerpt),
                "\(acceptanceCase.name) missing reason \(expectedInvalidReasonExcerpt)",
                file: file,
                line: line
            )
        }

        XCTAssertTrue(formatted.contains("timestamp_ms | phase | reps | counted | produced | hold | form | cue | score | invalid"))
        XCTAssertTrue(formatted.contains("plank_line=valid(") || formatted.contains("plank_line=invalid("))

        print(
            [
                "plank-acceptance",
                "case=\(acceptanceCase.name)",
                "frames=\(acceptanceCase.frames.count)",
                "held=\(Self.heldSummary(trace))",
                "expected_target=\(acceptanceCase.expectedTargetReachedTimestamps)",
                "actual_target=\(targetReachedTimestamps)",
                "expected_resets=\(acceptanceCase.expectedResetTimestamps)",
                "actual_resets=\(resetTimestamps)"
            ].joined(separator: " ")
        )
        print("plank-acceptance-trace-\(acceptanceCase.name)\n\(Self.holdRows(formatted))")
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
        packageRoot.appendingPathComponent("Presets/bodyweight_plank.json")
    }

    private static func heldSummary(_ trace: [EngineTraceFrame]) -> String {
        trace.map { frame in
            let heldSeconds = frame.hold.map { String(format: "%.3f", $0.heldSeconds) } ?? "nil"
            let targetReached = frame.hold?.targetReached ?? false
            return "\(frame.timestampMS):\(heldSeconds):target=\(targetReached)"
        }.joined(separator: ",")
    }

    private static func holdRows(_ output: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains("held=") }
            .joined(separator: "\n")
    }
}

private struct AcceptanceCase {
    let name: String
    let frames: [PoseFrame]
    let expectedHeldSeconds: [Int64: Double]
    let expectedTargetReachedTimestamps: [Int64]
    let expectedResetTimestamps: [Int64]
    let expectedInvalidReasonExcerpt: String?
}
