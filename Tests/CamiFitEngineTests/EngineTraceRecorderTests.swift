import XCTest
@testable import CamiFitEngine

final class EngineTraceRecorderTests: XCTestCase {
    func testTraceFramesPreserveTimestampsAndCaptureRepProgress() throws {
        var recorder = try Self.recorder()
        let frames = Self.validRepFrames(startMS: 0)

        let trace = recorder.record(frames: frames)

        XCTAssertEqual(trace.map(\.timestampMS), frames.map(\.timestampMS))
        let counted = try XCTUnwrap(trace.first { $0.rep.countedThisFrame })

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.rep.repCount, 1)
        XCTAssertEqual(counted.timestampMS, 1_600)
        XCTAssertTrue(trace.contains { $0.rep.phase == .bottom })

        print("engine-trace-progress \(Self.excerpt(trace))")
    }

    func testTraceFramesCaptureFormSnapshotsAndScoreSummaries() throws {
        var recorder = try Self.recorder()

        let trace = recorder.record(frames: Self.validRepFrames(startMS: 0))
        let bottom = try XCTUnwrap(trace.first { $0.rep.phase == .bottom })

        XCTAssertEqual(bottom.formSnapshots.map(\.ruleID), ["depth", "torso", "symmetry"])
        XCTAssertEqual(bottom.formSummary.score, 1.0)
        XCTAssertEqual(bottom.formSummary.possibleWeight, 22)
        XCTAssertNil(bottom.formSummary.selectedCue)

        print("engine-trace-form timestamp=\(bottom.timestampMS) form=\(Self.format(bottom.formSnapshots)) summary=\(bottom.formSummary)")
    }

    func testTraceProducedValuesAreDeterministicAndIncludeSquatInspectionSignals() throws {
        var recorder = try Self.recorder()

        let traceFrame = try XCTUnwrap(recorder.record(frames: [Self.standingFrame(timestampMS: 0)]).first)
        let keys = traceFrame.producedValues.map(\.key)

        XCTAssertEqual(keys, keys.sorted())
        XCTAssertTrue(keys.contains("knee"))
        XCTAssertTrue(keys.contains("torso_tilt"))
        XCTAssertTrue(keys.contains("knee_symmetry"))

        print("engine-trace-produced-values \(traceFrame.producedValues.map(\.description).joined(separator: " | "))")
    }

    func testTraceRecordsInvalidProducedValuesAndRepInvalidReason() throws {
        var recorder = try Self.recorder()

        let traceFrame = try XCTUnwrap(recorder.record(frames: [Self.lowVisibilityFrame(timestampMS: 0)]).first)
        let knee = try XCTUnwrap(traceFrame.producedValues.first { $0.key == "knee" })

        guard case let .invalid(reason) = knee.value else {
            return XCTFail("expected invalid knee trace value, got \(knee.value)")
        }

        XCTAssertTrue(reason.contains("low confidence"))
        XCTAssertTrue(traceFrame.rep.invalidReason?.contains("phase signal knee invalid") == true)
        XCTAssertEqual(traceFrame.formSummary.score, nil)

        print("engine-trace-invalid timestamp=\(traceFrame.timestampMS) \(knee) rep=\(traceFrame.rep) summary=\(traceFrame.formSummary)")
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

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func validRepFrames(startMS: Int64) -> [PoseFrame] {
        [standingFrame(timestampMS: startMS)] +
            deepFrames(startMS: startMS + 100, count: 10) +
            standingFrames(startMS: startMS + 1_100, count: 8)
    }

    private static func standingFrames(startMS: Int64, count: Int, intervalMS: Int64 = 100) -> [PoseFrame] {
        (0 ..< count).map { index in
            standingFrame(timestampMS: startMS + Int64(index) * intervalMS)
        }
    }

    private static func deepFrames(startMS: Int64, count: Int, intervalMS: Int64 = 100) -> [PoseFrame] {
        (0 ..< count).map { index in
            deepSquatFrame(timestampMS: startMS + Int64(index) * intervalMS)
        }
    }

    private static func standingFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: standingLandmarks)
    }

    private static func deepSquatFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: deepSquatLandmarks)
    }

    private static func lowVisibilityFrame(timestampMS: Int64) -> PoseFrame {
        var landmarks = standingLandmarks
        landmarks["primary.knee"] = PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 0.2, presence: 1)
        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static var standingLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0, ankleYOffset: 0.2)
    }

    private static var deepSquatLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0.2, ankleYOffset: 0)
    }

    private static func landmarks(ankleXOffset: Double, ankleYOffset: Double) -> [String: PoseLandmark] {
        [
            "left.shoulder": PoseLandmark(x: 0.35, y: 0.24, z: 0, visibility: 1, presence: 1),
            "left.hip": PoseLandmark(x: 0.35, y: 0.44, z: 0, visibility: 1, presence: 1),
            "left.knee": PoseLandmark(x: 0.35, y: 0.64, z: 0, visibility: 1, presence: 1),
            "left.ankle": PoseLandmark(x: 0.35 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1),
            "right.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "right.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "right.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "right.ankle": PoseLandmark(x: 0.65 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1),
            "primary.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "primary.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "primary.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "primary.ankle": PoseLandmark(x: 0.65 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1)
        ]
    }

    private static func excerpt(_ trace: [EngineTraceFrame]) -> String {
        trace.map { frame in
            "\(frame.timestampMS):\(frame.rep.phase.rawValue):reps=\(frame.rep.repCount):counted=\(frame.rep.countedThisFrame)"
        }.joined(separator: " ")
    }

    private static func format(_ snapshots: [FormRuleSnapshot]) -> String {
        snapshots.map(\.description).joined(separator: " | ")
    }
}
