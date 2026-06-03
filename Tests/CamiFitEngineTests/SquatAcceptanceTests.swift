import XCTest
@testable import CamiFitEngine

final class SquatAcceptanceTests: XCTestCase {
    func testBodyweightSquatAcceptanceFixtures() throws {
        let cases = try [
            AcceptanceCase(
                name: "clean",
                frames: Self.loadPoseFixture("synthetic_squat_clean_trace.json").frames,
                expectedRepCount: 1,
                expectedCountedTimestamps: [1_600],
                countedToleranceMS: 50,
                invalidInterval: nil,
                expectedInvalidEvidence: nil
            ),
            AcceptanceCase(
                name: "shallow",
                frames: Self.loadPoseFixture("synthetic_squat_shallow_trace.json").frames,
                expectedRepCount: 0,
                expectedCountedTimestamps: [],
                countedToleranceMS: 50,
                invalidInterval: nil,
                expectedInvalidEvidence: nil
            ),
            AcceptanceCase(
                name: "low_visibility",
                frames: Self.loadPoseFixture("synthetic_squat_low_visibility_trace.json").frames,
                expectedRepCount: 0,
                expectedCountedTimestamps: [],
                countedToleranceMS: 50,
                invalidInterval: 100 ... 300,
                expectedInvalidEvidence: "low confidence landmark primary.knee"
            ),
            AcceptanceCase(
                name: "mediapipe_no_pose",
                frames: MediaPipePoseProvider(jsonlURL: Self.fixtureURL("mediapipe_pose_worker_mixed_no_pose.jsonl")).frames(),
                expectedRepCount: 0,
                expectedCountedTimestamps: [],
                countedToleranceMS: 50,
                invalidInterval: 2_100 ... 2_100,
                expectedInvalidEvidence: "missing landmark primary.hip"
            )
        ]

        for acceptanceCase in cases {
            try Self.assertAcceptance(acceptanceCase)
        }
    }

    private static func assertAcceptance(_ acceptanceCase: AcceptanceCase, file: StaticString = #filePath, line: UInt = #line) throws {
        var recorder = try EngineTraceRecorder(program: ProgramLoader.load(from: presetURL))
        let trace = recorder.record(frames: acceptanceCase.frames)
        let formatted = EngineTraceFormatter.format(trace)
        let countedTimestamps = trace.filter(\.rep.countedThisFrame).map(\.timestampMS)
        let finalRepCount = trace.last?.rep.repCount ?? 0

        XCTAssertEqual(finalRepCount, acceptanceCase.expectedRepCount, acceptanceCase.name, file: file, line: line)
        XCTAssertEqual(
            countedTimestamps.count,
            acceptanceCase.expectedCountedTimestamps.count,
            "\(acceptanceCase.name) counted timestamp count",
            file: file,
            line: line
        )

        for (actual, expected) in zip(countedTimestamps, acceptanceCase.expectedCountedTimestamps) {
            XCTAssertLessThanOrEqual(
                abs(actual - expected),
                acceptanceCase.countedToleranceMS,
                "\(acceptanceCase.name) counted timestamp \(actual) not within \(acceptanceCase.countedToleranceMS)ms of \(expected)",
                file: file,
                line: line
            )
        }

        var falseCountsInInvalidInterval = 0
        if let invalidInterval = acceptanceCase.invalidInterval {
            falseCountsInInvalidInterval = trace.filter {
                invalidInterval.contains($0.timestampMS) && $0.rep.countedThisFrame
            }.count
            XCTAssertEqual(falseCountsInInvalidInterval, 0, acceptanceCase.name, file: file, line: line)
        }

        if let expectedInvalidEvidence = acceptanceCase.expectedInvalidEvidence {
            XCTAssertTrue(
                formatted.contains(expectedInvalidEvidence),
                "\(acceptanceCase.name) missing invalid evidence \(expectedInvalidEvidence)",
                file: file,
                line: line
            )
        }

        let invalidIntervalDescription = acceptanceCase.invalidInterval.map {
            "\($0.lowerBound)...\($0.upperBound)"
        } ?? "nil"

        print(
            [
                "squat-acceptance",
                "case=\(acceptanceCase.name)",
                "frames=\(acceptanceCase.frames.count)",
                "expected_reps=\(acceptanceCase.expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "expected_counted=\(acceptanceCase.expectedCountedTimestamps)",
                "actual_counted=\(countedTimestamps)",
                "tolerance_ms=\(acceptanceCase.countedToleranceMS)",
                "invalid_interval=\(invalidIntervalDescription)",
                "false_counts_invalid=\(falseCountsInInvalidInterval)"
            ].joined(separator: " ")
        )

        if acceptanceCase.expectedInvalidEvidence != nil {
            print("squat-acceptance-invalid-\(acceptanceCase.name)\n\(Self.rowsContaining(formatted, "invalid="))")
        }
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
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}

private struct AcceptanceCase {
    let name: String
    let frames: [PoseFrame]
    let expectedRepCount: Int
    let expectedCountedTimestamps: [Int64]
    let countedToleranceMS: Int64
    let invalidInterval: ClosedRange<Int64>?
    let expectedInvalidEvidence: String?
}
