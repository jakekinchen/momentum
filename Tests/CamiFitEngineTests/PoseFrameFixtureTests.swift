import XCTest
@testable import CamiFitEngine

final class PoseFrameFixtureTests: XCTestCase {
    func testFixtureLoaderPreservesFrameMetadataAndRequiredLandmarks() throws {
        let fixture = try Self.fixture()

        XCTAssertEqual(fixture.frames.count, 17)
        XCTAssertEqual(fixture.frames.first?.timestampMS, 0)
        XCTAssertEqual(fixture.frames.last?.timestampMS, 1_600)
        XCTAssertEqual(Set(fixture.frames.map(\.imageWidth)), [1_280.0])
        XCTAssertEqual(Set(fixture.frames.map(\.imageHeight)), [720.0])

        let first = try XCTUnwrap(fixture.frames.first)
        for landmarkID in ["primary.hip", "primary.knee", "primary.ankle", "primary.shoulder"] {
            let landmark = try XCTUnwrap(first.landmarks[landmarkID])
            XCTAssertEqual(landmark.visibility, 1)
            XCTAssertEqual(landmark.presence, 1)
        }

        print("pose-fixture-summary frames=\(fixture.frames.count) first=\(first.timestampMS) last=\(fixture.frames.last?.timestampMS ?? -1) size=\(first.imageWidth)x\(first.imageHeight)")
    }

    func testLoadedFixtureRunsThroughTraceRecorderAndFormatter() throws {
        let fixture = try Self.fixture()
        var recorder = try Self.recorder()

        let trace = recorder.record(frames: fixture.frames)
        let formatted = EngineTraceFormatter.format(trace)
        let counted = try XCTUnwrap(trace.first { $0.rep.countedThisFrame })
        let bottom = try XCTUnwrap(trace.first { $0.rep.phase == .bottom })

        XCTAssertEqual(counted.timestampMS, 1_600)
        XCTAssertEqual(counted.rep.repCount, 1)
        XCTAssertTrue(formatted.contains("1600 | ready | 1 | true"))
        XCTAssertEqual(bottom.formSnapshots.map(\.ruleID), ["depth", "torso", "symmetry"])
        XCTAssertEqual(bottom.formSummary.score, 1.0)
        XCTAssertEqual(formatted, EngineTraceFormatter.format(trace))

        print("pose-fixture-counted\n\(Self.rowsContaining(formatted, "1600 |"))")
        print("pose-fixture-bottom timestamp=\(bottom.timestampMS) form=\(bottom.formSnapshots.map(\.description).joined(separator: " | ")) summary=\(bottom.formSummary)")
    }

    func testLowVisibilityFixtureRecordsInvalidEvidenceWithoutFalseCounts() throws {
        let fixture = try Self.lowVisibilityFixture()
        var recorder = try Self.recorder()

        let trace = recorder.record(frames: fixture.frames)
        let formatted = EngineTraceFormatter.format(trace)
        let invalidFrames = trace.filter { $0.rep.invalidReason != nil }
        let lowVisibilityInterval: ClosedRange<Int64> = 100 ... 300
        let countedInInvalidInterval = trace.filter {
            lowVisibilityInterval.contains($0.timestampMS) && $0.rep.countedThisFrame
        }
        let invalidKneeFrames = trace.filter { frame in
            frame.producedValues.contains { produced in
                if produced.key != "knee" {
                    return false
                }

                guard case .invalid = produced.value else {
                    return false
                }

                return true
            }
        }

        XCTAssertEqual(fixture.frames.count, 5)
        XCTAssertEqual(invalidFrames.map(\.timestampMS), [100, 200, 300])
        XCTAssertEqual(invalidKneeFrames.map(\.timestampMS), [100, 200, 300])
        XCTAssertTrue(countedInInvalidInterval.isEmpty)
        XCTAssertEqual(trace.last?.rep.repCount, 0)
        XCTAssertTrue(formatted.contains("knee=invalid("))
        XCTAssertTrue(formatted.contains("phase signal knee invalid"))

        print("pose-fixture-low-visibility frames=\(fixture.frames.count) invalid=\(invalidFrames.map(\.timestampMS)) counted_in_invalid=\(countedInInvalidInterval.count) final_reps=\(trace.last?.rep.repCount ?? -1)")
        print("pose-fixture-low-visibility-invalid\n\(Self.rowsContaining(formatted, "phase signal knee invalid"))")
    }

    private static func fixture() throws -> PoseFrameFixture {
        try PoseFrameFixtureLoader.load(from: fixtureURL)
    }

    private static func lowVisibilityFixture() throws -> PoseFrameFixture {
        try PoseFrameFixtureLoader.load(from: lowVisibilityFixtureURL)
    }

    private static func recorder() throws -> EngineTraceRecorder {
        try EngineTraceRecorder(program: ProgramLoader.load(from: presetURL))
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var fixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/synthetic_squat_clean_trace.json")
    }

    private static var lowVisibilityFixtureURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/synthetic_squat_low_visibility_trace.json")
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
