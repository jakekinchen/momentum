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

    private static func fixture() throws -> PoseFrameFixture {
        try PoseFrameFixtureLoader.load(from: fixtureURL)
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
