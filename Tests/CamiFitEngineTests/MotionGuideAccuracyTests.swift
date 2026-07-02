import XCTest
@testable import CamiFitEngine

/// Scores every shipped guide motion path for accuracy and enforces two gates:
///
/// 1. The protected bodyweight lunge trace is the golden test — its full
///    accuracy report is pinned, so any change to the trace, decoder, or
///    scorer that moves lunge accuracy fails loudly.
/// 2. Every exercise is scored against committed per-exercise ceilings in
///    `Fixtures/motion_accuracy_baseline.json` (a ratchet: guides may improve,
///    never regress) plus absolute invariants (one rep or hold reached, full
///    ROM, closed loop).
///
/// The fleet test also writes `dist/motion-accuracy/scorecard.json` so guide
/// accuracy can be reviewed without rerunning the suite.
/// See docs/design/2026-06-09-guide-motion-accuracy-harness.md.
final class MotionGuideAccuracyTests: XCTestCase {
    private static let presetNames = [
        "bodyweight_squat",
        "bodyweight_lunge",
        "bodyweight_pushup",
        "bodyweight_plank",
        "standing_miniband_hip_flexion",
        "resistance_band_reverse_curl",
        "bodyweight_pike",
        "single_arm_dumbbell_preacher_curl",
        "bench_lying_single_arm_dumbbell_tricep_extension",
        "single_arm_cable_tricep_extension",
        "suspension_tricep_press",
        "wide_grip_preacher_curl_with_ez_bar",
        "single_arm_chest_supported_incline_row",
        "machine_chest_supported_row"
    ]

    func testGoldenLungeRecordedTraceAccuracyStaysPinned() throws {
        let report = try Self.scoreShippedGuide("bodyweight_lunge")

        XCTAssertEqual(report.sourceKind, "trainer_reference_trace")
        XCTAssertEqual(report.frameCount, 108)
        XCTAssertEqual(report.repCount, 1)
        XCTAssertEqual(report.holdTargetReached, nil)

        XCTAssertEqual(report.boneLengthMaxCV, 0.3248, accuracy: 0.005)
        XCTAssertEqual(report.worstSegment, "secondary.knee→secondary.ankle")
        XCTAssertEqual(try XCTUnwrap(report.observedROMDegrees), 78.3, accuracy: 0.5)
        XCTAssertEqual(report.peakLandmarkSpeedBodyPerSecond, 0.4627, accuracy: 0.01)
        XCTAssertLessThanOrEqual(report.loopClosureGapBodyScaled, 0.0001)
        // Keyframe smoothing (2026-06-10) brought the played-back trace's median
        // noise-to-signal from 1.11 (visible jitter) to ~0.30.
        XCTAssertEqual(report.noiseToSignalMedian, 0.304, accuracy: 0.01)

        // The guide is the exemplar: replaying it through its own preset must
        // produce zero form-rule violations (depth is episode-extreme evaluated
        // with the threshold calibrated to the reference motion, 2026-06-10).
        XCTAssertEqual(report.formViolationFrames, 0)
        XCTAssertEqual(report.violatedRuleIDs, [])
    }

    func testAllShippedGuidesMeetAccuracyBaseline() throws {
        let baseline = try Self.loadBaseline()
        var entries: [ScorecardEntry] = []
        var failures: [String] = []

        for name in Self.presetNames {
            let report = try Self.scoreShippedGuide(name)
            var reasons: [String] = []

            guard let expected = baseline.exercises[name] else {
                failures.append("\(name): missing entry in motion_accuracy_baseline.json")
                continue
            }

            if report.sourceKind != expected.sourceKind {
                reasons.append("source kind changed from \(expected.sourceKind) to \(report.sourceKind)")
            }

            let thresholds = MotionGuideAccuracyThresholds(
                maxBoneLengthCV: expected.maxBoneLengthCV,
                maxPeakLandmarkSpeedBodyPerSecond: expected.maxPeakLandmarkSpeedBodyPerSecond,
                maxLoopClosureGapBodyScaled: expected.maxLoopClosureGapBodyScaled,
                maxFormViolationFrames: expected.maxFormViolationFrames,
                maxNoiseToSignalMedian: expected.maxNoiseToSignalMedian
            )
            reasons.append(contentsOf: thresholds.failureReasons(for: report))

            entries.append(ScorecardEntry(
                report: report,
                exemplarClean: report.formViolationFrames == 0,
                regressions: reasons
            ))
            if !reasons.isEmpty {
                failures.append("\(name): \(reasons.joined(separator: "; "))")
            }

            print(
                "motion-accuracy exercise=\(name) source=\(report.sourceKind) " +
                "bone_cv=\(String(format: "%.3f", report.boneLengthMaxCV)) " +
                "peak_speed=\(String(format: "%.2f", report.peakLandmarkSpeedBodyPerSecond)) " +
                "noise=\(String(format: "%.2f", report.noiseToSignalMedian)) " +
                "violations=\(report.formViolationFrames)\(report.violatedRuleIDs.isEmpty ? "" : " rules=" + report.violatedRuleIDs.joined(separator: ",")) " +
                "status=\(reasons.isEmpty ? "ok" : "REGRESSED")"
            )
        }

        try Self.writeScorecard(entries)
        XCTAssertTrue(failures.isEmpty, "guide accuracy regressed:\n" + failures.joined(separator: "\n"))
    }

    // MARK: - Scoring the shipped guide

    /// Scores what the app actually plays: the packaged recorded JSONL when
    /// one is bundled, otherwise the procedural compiler output.
    private static func scoreShippedGuide(_ name: String) throws -> MotionGuideAccuracyReport {
        let program = try ProgramLoader.load(from: presetURL(name))
        let recordedURL = motionDemoURL(name)

        if FileManager.default.fileExists(atPath: recordedURL.path) {
            // Recorded traces are keyframe-smoothed at timeline construction
            // (MotionDemoBundleStore); score the frames the app actually plays.
            let frames = MotionDemoKeyframeSmoother.smooth(
                try MediaPipePoseProvider(jsonlURL: recordedURL).frames()
            )
            return try MotionGuideAccuracyScorer.score(
                program: program,
                frames: frames,
                sourceKind: bundledSourceKind(nextTo: recordedURL) ?? .trainerReferenceTrace
            )
        }

        let timeline = MotionDemoCompiler.compile(program: program)
        return try MotionGuideAccuracyScorer.score(
            program: program,
            frames: timeline.frames,
            sourceKind: .proceduralFallback
        )
    }

    private struct BundledManifestSourceKind: Decodable {
        let sourceKind: MotionDemoSourceKind?

        private enum CodingKeys: String, CodingKey {
            case sourceKind = "source_kind"
        }
    }

    private static func bundledSourceKind(nextTo traceURL: URL) -> MotionDemoSourceKind? {
        let manifestURL = traceURL
            .deletingPathExtension()
            .appendingPathExtension("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BundledManifestSourceKind.self, from: data) else {
            return nil
        }
        return manifest.sourceKind
    }

    // MARK: - Baseline and scorecard

    private struct Baseline: Decodable {
        struct Expectation: Decodable {
            let sourceKind: String
            let maxBoneLengthCV: Double
            let maxPeakLandmarkSpeedBodyPerSecond: Double
            let maxLoopClosureGapBodyScaled: Double
            let maxFormViolationFrames: Int
            let maxNoiseToSignalMedian: Double

            private enum CodingKeys: String, CodingKey {
                case sourceKind = "source_kind"
                case maxBoneLengthCV = "max_bone_length_cv"
                case maxPeakLandmarkSpeedBodyPerSecond = "max_peak_landmark_speed_body_per_second"
                case maxLoopClosureGapBodyScaled = "max_loop_closure_gap_body_scaled"
                case maxFormViolationFrames = "max_form_violation_frames"
                case maxNoiseToSignalMedian = "max_noise_to_signal_median"
            }
        }

        let exercises: [String: Expectation]
    }

    private struct ScorecardEntry: Encodable {
        let report: MotionGuideAccuracyReport
        let exemplarClean: Bool
        let regressions: [String]

        private enum CodingKeys: String, CodingKey {
            case report
            case exemplarClean = "exemplar_clean"
            case regressions
        }
    }

    private static func loadBaseline() throws -> Baseline {
        let url = packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/motion_accuracy_baseline.json")
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    private static func writeScorecard(_ entries: [ScorecardEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let url = packageRoot.appendingPathComponent("dist/motion-accuracy/scorecard.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: url)
    }

    // MARK: - Paths

    private static func presetURL(_ name: String) -> URL {
        packageRoot.appendingPathComponent("Presets/\(name).json")
    }

    private static func motionDemoURL(_ name: String) -> URL {
        packageRoot.appendingPathComponent("Sources/CamiFitApp/Resources/MotionDemos/\(name).jsonl")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
