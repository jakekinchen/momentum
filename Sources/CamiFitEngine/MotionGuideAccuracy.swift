import Foundation

public struct MotionGuideAccuracyReport: Codable, Equatable {
    public struct SegmentVariation: Codable, Equatable {
        public let segment: String
        public let meanLength: Double
        public let coefficientOfVariation: Double

        private enum CodingKeys: String, CodingKey {
            case segment
            case meanLength = "mean_length"
            case coefficientOfVariation = "coefficient_of_variation"
        }
    }

    public let exerciseID: String
    public let sourceKind: String
    public let frameCount: Int

    public let boneLengthMaxCV: Double
    public let worstSegment: String?
    public let measuredSegments: [SegmentVariation]

    public let repCount: Int?
    public let observedROMDegrees: Double?
    public let requiredROMDegrees: Double?
    public let holdTargetReached: Bool?
    public let formViolationFrames: Int
    public let violatedRuleIDs: [String]

    public let peakLandmarkSpeedBodyPerSecond: Double
    public let loopClosureGapBodyScaled: Double
    public let noiseToSignalMedian: Double

    private enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case sourceKind = "source_kind"
        case frameCount = "frame_count"
        case boneLengthMaxCV = "bone_length_max_cv"
        case worstSegment = "worst_segment"
        case measuredSegments = "measured_segments"
        case repCount = "rep_count"
        case observedROMDegrees = "observed_rom_degrees"
        case requiredROMDegrees = "required_rom_degrees"
        case holdTargetReached = "hold_target_reached"
        case formViolationFrames = "form_violation_frames"
        case violatedRuleIDs = "violated_rule_ids"
        case peakLandmarkSpeedBodyPerSecond = "peak_landmark_speed_body_per_second"
        case loopClosureGapBodyScaled = "loop_closure_gap_body_scaled"
        case noiseToSignalMedian = "noise_to_signal_median"
    }
}

public struct MotionGuideAccuracyThresholds {
    public var maxBoneLengthCV: Double
    public var maxPeakLandmarkSpeedBodyPerSecond: Double
    public var maxLoopClosureGapBodyScaled: Double
    public var maxFormViolationFrames: Int
    public var maxNoiseToSignalMedian: Double

    public init(
        maxBoneLengthCV: Double,
        maxPeakLandmarkSpeedBodyPerSecond: Double,
        maxLoopClosureGapBodyScaled: Double,
        maxFormViolationFrames: Int,
        maxNoiseToSignalMedian: Double
    ) {
        self.maxBoneLengthCV = maxBoneLengthCV
        self.maxPeakLandmarkSpeedBodyPerSecond = maxPeakLandmarkSpeedBodyPerSecond
        self.maxLoopClosureGapBodyScaled = maxLoopClosureGapBodyScaled
        self.maxFormViolationFrames = maxFormViolationFrames
        self.maxNoiseToSignalMedian = maxNoiseToSignalMedian
    }

    public func failureReasons(for report: MotionGuideAccuracyReport) -> [String] {
        var reasons: [String] = []

        if report.boneLengthMaxCV > maxBoneLengthCV {
            let segment = report.worstSegment ?? "unknown segment"
            reasons.append(String(
                format: "bone length varies %.1f%% across frames (%@, limit %.1f%%)",
                report.boneLengthMaxCV * 100, segment, maxBoneLengthCV * 100
            ))
        }

        if let repCount = report.repCount, repCount != 1 {
            reasons.append("engine replay counted \(repCount) reps instead of 1")
        }

        if let observed = report.observedROMDegrees, let required = report.requiredROMDegrees, observed < required {
            reasons.append(String(
                format: "phase signal range %.1f° is under the preset minimum ROM %.1f°",
                observed, required
            ))
        }

        if let holdTargetReached = report.holdTargetReached, !holdTargetReached {
            reasons.append("hold replay never reached the hold target")
        }

        if report.formViolationFrames > maxFormViolationFrames {
            let rules = report.violatedRuleIDs.joined(separator: ", ")
            reasons.append("guide violates its own form rules [\(rules)] on \(report.formViolationFrames) frames")
        }

        if report.peakLandmarkSpeedBodyPerSecond > maxPeakLandmarkSpeedBodyPerSecond {
            reasons.append(String(
                format: "peak landmark speed %.1f body-lengths/s exceeds %.1f",
                report.peakLandmarkSpeedBodyPerSecond, maxPeakLandmarkSpeedBodyPerSecond
            ))
        }

        if report.loopClosureGapBodyScaled > maxLoopClosureGapBodyScaled {
            reasons.append(String(
                format: "loop closure gap %.3f body-lengths exceeds %.3f",
                report.loopClosureGapBodyScaled, maxLoopClosureGapBodyScaled
            ))
        }

        if report.noiseToSignalMedian > maxNoiseToSignalMedian {
            reasons.append(String(
                format: "frame-to-frame jitter: median noise-to-signal ratio %.2f exceeds %.2f (guide will look shaky)",
                report.noiseToSignalMedian, maxNoiseToSignalMedian
            ))
        }

        return reasons
    }
}

public enum MotionGuideAccuracyScorer {
    private static let segmentJointPairs: [(String, String)] = [
        ("shoulder", "hip"),
        ("hip", "knee"),
        ("knee", "ankle"),
        ("shoulder", "elbow"),
        ("elbow", "wrist")
    ]

    private static let landmarkFamilies = ["primary", "secondary", "left", "right"]

    public static func score(
        program: ExerciseProgram,
        frames: [PoseFrame],
        sourceKind: MotionDemoSourceKind
    ) throws -> MotionGuideAccuracyReport {
        guard frames.count >= 2 else {
            throw ProgramLoadError.invalidStructure(
                field: "frames",
                reason: "accuracy scoring requires at least 2 pose frames"
            )
        }

        let bodyScale = medianBodyScale(frames: frames)
        let segments = segmentVariations(frames: frames)
        let worst = segments.max { $0.coefficientOfVariation < $1.coefficientOfVariation }
        let replay = try replayThroughEngine(program: program, frames: frames)

        return MotionGuideAccuracyReport(
            exerciseID: program.id,
            sourceKind: sourceKind.rawValue,
            frameCount: frames.count,
            boneLengthMaxCV: worst?.coefficientOfVariation ?? 0,
            worstSegment: worst?.segment,
            measuredSegments: segments,
            repCount: replay.repCount,
            observedROMDegrees: replay.observedROMDegrees,
            requiredROMDegrees: program.rep?.minROMDegrees,
            holdTargetReached: replay.holdTargetReached,
            formViolationFrames: replay.formViolationFrames,
            violatedRuleIDs: replay.violatedRuleIDs,
            peakLandmarkSpeedBodyPerSecond: peakLandmarkSpeed(frames: frames, bodyScale: bodyScale),
            loopClosureGapBodyScaled: loopClosureGap(frames: frames, bodyScale: bodyScale),
            noiseToSignalMedian: noiseToSignalMedian(frames: frames)
        )
    }

    /// Median ratio of frame-to-frame acceleration to velocity across all
    /// landmarks present in every frame. Above ~1, estimation noise exceeds
    /// the true per-frame motion and the guide visibly trembles. Scale-free,
    /// so no body normalization is needed.
    private static func noiseToSignalMedian(frames: [PoseFrame]) -> Double {
        guard frames.count >= 3 else { return 0 }

        var common = Set(frames[0].landmarks.keys)
        for frame in frames.dropFirst() {
            common.formIntersection(frame.landmarks.keys)
        }

        var ratios: [Double] = []
        for name in common {
            for index in 1..<(frames.count - 1) {
                guard let before = frames[index - 1].landmark(named: name),
                      let current = frames[index].landmark(named: name),
                      let after = frames[index + 1].landmark(named: name) else {
                    continue
                }

                let accelerationX = after.x - (2 * current.x) + before.x
                let accelerationY = after.y - (2 * current.y) + before.y
                let acceleration = (accelerationX * accelerationX + accelerationY * accelerationY).squareRoot()
                let velocityX = (after.x - before.x) / 2
                let velocityY = (after.y - before.y) / 2
                let velocity = (velocityX * velocityX + velocityY * velocityY).squareRoot()

                if acceleration > 0.000_001 || velocity > 0.000_001 {
                    ratios.append(acceleration / max(velocity, 0.000_001))
                }
            }
        }

        return median(ratios) ?? 0
    }

    // MARK: - Skeleton integrity

    private static func segmentVariations(frames: [PoseFrame]) -> [MotionGuideAccuracyReport.SegmentVariation] {
        var variations: [MotionGuideAccuracyReport.SegmentVariation] = []

        for family in landmarkFamilies {
            for (jointA, jointB) in segmentJointPairs {
                let nameA = "\(family).\(jointA)"
                let nameB = "\(family).\(jointB)"
                var lengths: [Double] = []

                for frame in frames {
                    guard let a = frame.landmark(named: nameA), let b = frame.landmark(named: nameB) else {
                        lengths.removeAll()
                        break
                    }
                    lengths.append(distanceXY(a, b))
                }

                guard lengths.count == frames.count, let cv = coefficientOfVariation(lengths) else {
                    continue
                }

                variations.append(MotionGuideAccuracyReport.SegmentVariation(
                    segment: "\(nameA)→\(nameB)",
                    meanLength: mean(lengths),
                    coefficientOfVariation: cv
                ))
            }
        }

        return variations.sorted { $0.segment < $1.segment }
    }

    // MARK: - Engine replay

    private struct ReplayResult {
        let repCount: Int?
        let observedROMDegrees: Double?
        let holdTargetReached: Bool?
        let formViolationFrames: Int
        let violatedRuleIDs: [String]
    }

    private static func replayThroughEngine(program: ExerciseProgram, frames: [PoseFrame]) throws -> ReplayResult {
        let replayFrames: [PoseFrame]
        if let hold = program.hold {
            replayFrames = loopedFrames(frames, coveringSeconds: hold.targetSeconds + 2.0)
        } else {
            replayFrames = frames
        }

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: replayFrames)

        var violationFrames = 0
        var violatedRuleIDs = Set<String>()
        for traceFrame in trace {
            let violations = traceFrame.formSnapshots.filter { $0.isActive && $0.expectationPassed == false }
            if !violations.isEmpty {
                violationFrames += 1
                violations.forEach { violatedRuleIDs.insert($0.ruleID) }
            }
        }

        if program.rep != nil {
            let phaseSignal = program.rep?.phaseSignal ?? ""
            let phaseValues = trace.flatMap { frame in
                frame.producedValues.filter { $0.key == phaseSignal }.compactMap { $0.value.numericValue }
            }
            let observedROM = phaseValues.isEmpty ? nil : (phaseValues.max()! - phaseValues.min()!)

            return ReplayResult(
                repCount: trace.last?.rep.repCount ?? 0,
                observedROMDegrees: observedROM,
                holdTargetReached: nil,
                formViolationFrames: violationFrames,
                violatedRuleIDs: violatedRuleIDs.sorted()
            )
        }

        return ReplayResult(
            repCount: nil,
            observedROMDegrees: nil,
            holdTargetReached: trace.contains { $0.hold?.targetReached == true },
            formViolationFrames: violationFrames,
            violatedRuleIDs: violatedRuleIDs.sorted()
        )
    }

    private static func loopedFrames(_ frames: [PoseFrame], coveringSeconds: Double) -> [PoseFrame] {
        guard let first = frames.first, let last = frames.last else { return frames }

        let intervals = zip(frames, frames.dropFirst()).map { Double($1.timestampMS - $0.timestampMS) }
        let nominalInterval = max(median(intervals) ?? 100, 1)
        let strideMS = Int64(Double(last.timestampMS - first.timestampMS) + nominalInterval)
        let loops = max(Int((coveringSeconds * 1000 / Double(strideMS)).rounded(.up)), 1)

        var looped: [PoseFrame] = []
        for loop in 0..<min(loops, 200) {
            let offset = Int64(loop) * strideMS
            for frame in frames {
                looped.append(PoseFrame(
                    timestampMS: frame.timestampMS + offset,
                    imageWidth: frame.imageWidth,
                    imageHeight: frame.imageHeight,
                    landmarks: frame.landmarks
                ))
            }
        }
        return looped
    }

    // MARK: - Motion quality

    private static func peakLandmarkSpeed(frames: [PoseFrame], bodyScale: Double) -> Double {
        var peak = 0.0
        for (current, next) in zip(frames, frames.dropFirst()) {
            let dtSeconds = max(Double(next.timestampMS - current.timestampMS) / 1000, 0.001)
            for (name, landmark) in current.landmarks {
                guard let moved = next.landmark(named: name) else { continue }
                let speed = distanceXY(landmark, moved) / bodyScale / dtSeconds
                peak = max(peak, speed)
            }
        }
        return peak
    }

    private static func loopClosureGap(frames: [PoseFrame], bodyScale: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }

        var gap = 0.0
        for (name, landmark) in first.landmarks {
            guard let closing = last.landmark(named: name) else { continue }
            gap = max(gap, distanceXY(landmark, closing) / bodyScale)
        }
        return gap
    }

    // MARK: - Geometry helpers

    private static func medianBodyScale(frames: [PoseFrame]) -> Double {
        let scales = frames.compactMap { frame -> Double? in
            let legLengths = landmarkFamilies.compactMap { family -> Double? in
                guard let hip = frame.landmark(named: "\(family).hip"),
                      let ankle = frame.landmark(named: "\(family).ankle") else {
                    return nil
                }
                return distanceXY(hip, ankle)
            }
            if let longest = legLengths.max(), longest > 0 {
                return longest
            }
            return boundingBoxDiagonal(frame: frame)
        }
        guard let scale = median(scales), scale > 0 else { return 1 }
        return scale
    }

    private static func boundingBoxDiagonal(frame: PoseFrame) -> Double? {
        let points = frame.landmarks.values
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return nil
        }
        let diagonal = ((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY)).squareRoot()
        return diagonal > 0 ? diagonal : nil
    }

    private static func distanceXY(_ a: PoseLandmark, _ b: PoseLandmark) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let average = mean(values)
        guard average > 0 else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
        return variance.squareRoot() / average
    }
}
