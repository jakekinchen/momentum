import XCTest
import Foundation
@testable import CamiFitEngine

final class MachineChestSupportedRowAcceptanceTests: XCTestCase {
    func testMachineChestSupportedRowPresetLoadsAndAcceptanceTracesPass() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        XCTAssertEqual(program.id, "machine_chest_supported_row")
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

    func testCandidateExternalTraceDecodesAndCountsCleanRepButDoesNotShipAsGuide() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: Self.motionDemoURL)
        let manifest = try Self.manifest()
        let first = try XCTUnwrap(frames.first)
        let last = try XCTUnwrap(frames.last)

        XCTAssertEqual(manifest["source_kind"] as? String, "licensed_external_reference_trace")
        XCTAssertEqual(manifest["acceptance_status"] as? String, "pending_source_license_review")
        XCTAssertEqual(manifest["playable_trace_packaged"] as? Bool, false)
        XCTAssertEqual(manifest["retarget"] as? String, "source_timed_side_view_machine_chest_supported_row")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.appBundleMotionDemoURL.path))
        XCTAssertEqual(frames.count, 84)
        XCTAssertEqual(first.timestampMS, 0)
        XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $1.timestampMS > $0.timestampMS })

        for name in ["primary.shoulder", "primary.elbow", "primary.wrist", "primary.hip"] {
            let start = try XCTUnwrap(first.landmark(named: name), name)
            let end = try XCTUnwrap(last.landmark(named: name), name)
            XCTAssertEqual(start.x, end.x, accuracy: 0.000_001, "\(name) x loop boundary drifted")
            XCTAssertEqual(start.y, end.y, accuracy: 0.000_001, "\(name) y loop boundary drifted")
            XCTAssertEqual(start.z, end.z, accuracy: 0.000_001, "\(name) z loop boundary drifted")
        }

        let angles = frames.compactMap { frame -> Double? in
            guard let shoulder = frame.landmark(named: "primary.shoulder"),
                  let elbow = frame.landmark(named: "primary.elbow"),
                  let wrist = frame.landmark(named: "primary.wrist") else { return nil }
            return Self.angle(shoulder, elbow, wrist)
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(angles.min()), 95)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(angles.max()), 150)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: frames)
        let countedTimestamps = trace.filter(\.rep.countedThisFrame).map(\.timestampMS)

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(countedTimestamps.count, 1)
        let selectedCues = trace.compactMap { row -> String? in
            guard let cue = row.formSummary.selectedCue else { return nil }
            return "\(row.timestampMS):\(row.formSummary.selectedCueRuleID ?? "unknown"):\(cue)"
        }
        XCTAssertTrue(selectedCues.isEmpty, "clean bundled row trace produced form cues: \(selectedCues)")
        print(
            "machine-chest-supported-row-bundled frames=\(frames.count) " +
            "elbow=\(angles.min() ?? 0)..\(angles.max() ?? 0) counted=\(countedTimestamps)"
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
                "machine-chest-supported-row-acceptance",
                "case=\(name)",
                "frames=\(frames.count)",
                "expected_reps=\(expectedRepCount)",
                "actual_reps=\(finalRepCount)",
                "actual_counted=\(countedTimestamps)"
            ].joined(separator: " ")
        )
        print("machine-chest-supported-row-acceptance-trace-\(name)\n\(Self.rowsContaining(formatted, "row_elbow"))")
    }

    private static func shallowTrace(intervalMS: Int64 = 100) -> [PoseFrame] {
        [0, 0, 0.10, 0.20, 0.35, 0.45, 0.45, 0.35, 0.20, 0.10, 0, 0].enumerated().map { index, factor in
            frame(timestampMS: Int64(index) * intervalMS, factor: factor)
        }
    }

    private static func frame(timestampMS: Int64, factor: Double) -> PoseFrame {
        let primary: [String: PoseLandmark] = [
            "nose": point(0.430, 0.270, -0.03),
            "shoulder": point(0.460, 0.400, 0),
            "elbow": point(mix(0.550, 0.390, factor), mix(0.560, 0.500, factor), 0.03),
            "wrist": point(mix(0.660, 0.500, factor), mix(0.730, 0.550, factor), 0.08),
            "hip": point(0.580, 0.600, 0),
            "knee": point(0.720, 0.710, 0.02),
            "ankle": point(0.840, 0.830, 0.05)
        ]
        var landmarks: [String: PoseLandmark] = [
            "nose": primary["nose"]!,
            "primary.nose": primary["nose"]!
        ]
        for (joint, value) in primary {
            landmarks["primary.\(joint)"] = value
            landmarks["left.\(joint)"] = value
            if joint != "nose" {
                landmarks["right.\(joint)"] = point(value.x + 0.09, value.y, value.z + 0.12)
            }
        }
        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static func point(_ x: Double, _ y: Double, _ z: Double) -> PoseLandmark {
        PoseLandmark(x: x, y: y, z: z, visibility: 1, presence: 1)
    }

    private static func angle(_ a: PoseLandmark, _ b: PoseLandmark, _ c: PoseLandmark) -> Double {
        let ab = (x: a.x - b.x, y: a.y - b.y)
        let cb = (x: c.x - b.x, y: c.y - b.y)
        let denominator = max(hypot(ab.x, ab.y) * hypot(cb.x, cb.y), 0.000_001)
        let cosine = max(-1, min(1, ((ab.x * cb.x) + (ab.y * cb.y)) / denominator))
        return acos(cosine) * 180 / .pi
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
        packageRoot.appendingPathComponent("Presets/machine_chest_supported_row.json")
    }

    private static var motionDemoURL: URL {
        packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/motion_reference/machine_chest_supported_row/machine_chest_supported_row.external.jsonl")
    }

    private static var appBundleMotionDemoURL: URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos/machine_chest_supported_row.jsonl")
    }

    private static var manifestURL: URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos/machine_chest_supported_row.manifest.json")
    }

    private static func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func rowsContaining(_ output: String, _ needle: String) -> String {
        output
            .split(separator: "\n")
            .filter { $0.contains(needle) }
            .joined(separator: "\n")
    }
}
