import XCTest
import CamiFitEngine
@testable import CamiFitApp

/// Integration check against real camera frames previously captured by the
/// app's record toggle (Application Support/CamiFit/Capture). Skips on
/// machines without captures, so CI stays hermetic while local runs verify
/// the Vision backend on genuine workout footage.
final class VisionPoseBackendCapturedFramesTests: XCTestCase {
    func testVisionDetectsPosesOnCapturedLiveFrames() throws {
        let directory = LiveSession.defaultRecordDirectory()
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            throw XCTSkip("no captured live frames at \(directory.path)")
        }
        let jpegs = names.filter { $0.hasSuffix(".jpg") }.sorted()
        try XCTSkipIf(jpegs.isEmpty, "no captured jpg frames at \(directory.path)")

        let backend = VisionPoseBackend()
        try backend.start()
        defer { backend.stop() }

        let step = max(jpegs.count / 20, 1)
        var sampled = 0
        var detected = 0
        var primaryConfidences: [Double] = []
        var totalSeconds = 0.0

        for (index, name) in jpegs.enumerated() where index % step == 0 {
            sampled += 1
            let begin = Date()
            let frame = try backend.predict(
                imagePath: directory.appendingPathComponent(name).path,
                frameID: index,
                timestampMS: Int64(index) * 83
            )
            totalSeconds += Date().timeIntervalSince(begin)

            guard let frame else { continue }
            detected += 1

            for joint in ["primary.shoulder", "primary.hip", "primary.knee", "primary.ankle"] {
                let landmark = try XCTUnwrap(frame.landmark(named: joint), "\(name) missing \(joint)")
                XCTAssertGreaterThanOrEqual(landmark.x, -0.5, "\(name) \(joint) x out of range")
                XCTAssertLessThanOrEqual(landmark.x, 1.5, "\(name) \(joint) x out of range")
                XCTAssertGreaterThanOrEqual(landmark.y, -0.5, "\(name) \(joint) y out of range")
                XCTAssertLessThanOrEqual(landmark.y, 1.5, "\(name) \(joint) y out of range")
                primaryConfidences.append(landmark.confidence)
            }
        }

        let detectionRate = Double(detected) / Double(max(sampled, 1))
        let meanConfidence = primaryConfidences.isEmpty
            ? 0
            : primaryConfidences.reduce(0, +) / Double(primaryConfidences.count)
        print(
            "vision-live-frames sampled=\(sampled) detected=\(detected) " +
            "rate=\(String(format: "%.2f", detectionRate)) " +
            "mean_primary_confidence=\(String(format: "%.2f", meanConfidence)) " +
            "mean_latency_ms=\(String(format: "%.1f", totalSeconds / Double(max(sampled, 1)) * 1000))"
        )

        // Floor calibrated by an A/B against the MediaPipe worker on this same
        // corpus (2026-06-09): the capture includes walk-in/walk-out frames with
        // no subject or with feet out of frame, which neither backend can track
        // (MediaPipe emits them with ankle visibility 0.04–0.3, below the
        // engine's 0.65 validity gate). Engine-usable rate was 12/23 for
        // MediaPipe and 13/23 for Vision — parity on every fully-framed frame.
        XCTAssertGreaterThanOrEqual(detectionRate, 0.5, "Vision should track every fully-framed frame, roughly half this corpus")
        XCTAssertGreaterThan(meanConfidence, 0.5, "primary joints should be confidently tracked")
    }
}
