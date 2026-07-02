import Foundation

public struct MotionDemoTimeline: Equatable {
    public let programID: String
    public let programName: String
    public let source: MotionDemoSource
    public let frames: [PoseFrame]
    public let durationMS: Int64

    public init(
        programID: String,
        programName: String,
        source: MotionDemoSource = .trainerReferenceFallback,
        frames: [PoseFrame],
        durationMS: Int64
    ) {
        self.programID = programID
        self.programName = programName
        self.source = source
        self.frames = frames.sorted { $0.timestampMS < $1.timestampMS }
        self.durationMS = max(durationMS, 1)
    }

    public func frame(atElapsedMS elapsedMS: Int64) -> PoseFrame {
        guard let first = frames.first else {
            return PoseFrame(timestampMS: 0, imageWidth: 1280, imageHeight: 720, landmarks: [:])
        }

        guard frames.count > 1 else {
            return first
        }

        let wrapped = ((elapsedMS % durationMS) + durationMS) % durationMS
        let currentIndex = frames.lastIndex { $0.timestampMS <= wrapped } ?? 0
        let current = frames[currentIndex]
        let nextIndex = frames.index(after: currentIndex)

        if nextIndex < frames.endIndex {
            return interpolate(from: current, to: frames[nextIndex], timestampMS: wrapped)
        }

        let loopedNext = frames[0]
        let shiftedNext = PoseFrame(
            timestampMS: loopedNext.timestampMS + durationMS,
            imageWidth: loopedNext.imageWidth,
            imageHeight: loopedNext.imageHeight,
            landmarks: loopedNext.landmarks
        )
        return interpolate(from: current, to: shiftedNext, timestampMS: wrapped)
    }

    private func interpolate(from start: PoseFrame, to end: PoseFrame, timestampMS: Int64) -> PoseFrame {
        let span = max(Double(end.timestampMS - start.timestampMS), 1)
        let progress = min(max(Double(timestampMS - start.timestampMS) / span, 0), 1)
        let keys = Set(start.landmarks.keys).union(end.landmarks.keys)
        var landmarks: [String: PoseLandmark] = [:]

        for key in keys {
            guard let a = start.landmarks[key] ?? end.landmarks[key],
                  let b = end.landmarks[key] ?? start.landmarks[key] else {
                continue
            }

            landmarks[key] = PoseLandmark(
                x: Self.mix(a.x, b.x, progress),
                y: Self.mix(a.y, b.y, progress),
                z: Self.mix(a.z, b.z, progress),
                visibility: Self.mix(a.visibility, b.visibility, progress),
                presence: Self.mix(a.presence, b.presence, progress)
            )
        }

        return PoseFrame(
            timestampMS: timestampMS,
            imageWidth: start.imageWidth,
            imageHeight: start.imageHeight,
            landmarks: landmarks
        )
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + ((b - a) * t)
    }

}

public enum MotionDemoSourceKind: String, Codable, Equatable {
    case trainerReferenceTrace = "trainer_reference_trace"
    case licensedExternalReferenceTrace = "licensed_external_reference_trace"
    case canonicalArchetypeAuthored = "canonical_archetype_authored"
    case canonicalArchetypeTrace = "canonical_archetype_trace"
    case proceduralFallback = "procedural_fallback"
}

public struct MotionDemoSource: Equatable {
    public let current: MotionDemoSourceKind
    public let canonical: MotionDemoSourceKind
    public let provenance: String

    public init(current: MotionDemoSourceKind, canonical: MotionDemoSourceKind, provenance: String) {
        self.current = current
        self.canonical = canonical
        self.provenance = provenance
    }

    public static let trainerReferenceFallback = MotionDemoSource(
        current: .proceduralFallback,
        canonical: .trainerReferenceTrace,
        provenance: "Procedural fallback until a trainer reference video trace is captured, normalized, and bundled."
    )

    public static func trainerReferenceTrace(provenance: String) -> MotionDemoSource {
        MotionDemoSource(
            current: .trainerReferenceTrace,
            canonical: .trainerReferenceTrace,
            provenance: provenance
        )
    }

    public static func canonicalArchetypeTrace(provenance: String) -> MotionDemoSource {
        MotionDemoSource(
            current: .canonicalArchetypeTrace,
            canonical: .trainerReferenceTrace,
            provenance: provenance
        )
    }

    public static func canonicalArchetypeAuthored(provenance: String) -> MotionDemoSource {
        MotionDemoSource(
            current: .canonicalArchetypeAuthored,
            canonical: .canonicalArchetypeAuthored,
            provenance: provenance
        )
    }
}

public enum MotionDemoCompiler {
    public static func compile(program: ExerciseProgram, frameIntervalMS: Int64 = 100) -> MotionDemoTimeline {
        let frames: [PoseFrame]
        if program.id.contains("suspension_tricep_press") {
            frames = suspensionTricepPressFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("cable_tricep_extension") {
            frames = cableTricepExtensionFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("tricep_extension") {
            frames = lyingTricepExtensionFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("preacher_curl") {
            frames = preacherCurlFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("row") || program.rep?.phaseSignal == "row_elbow" {
            frames = chestSupportedRowFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("reverse_curl") || program.rep?.phaseSignal == "curl_elbow" {
            frames = reverseCurlFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("hip_flexion") || program.rep?.phaseSignal == "hip_flexion" {
            frames = hipFlexionFrames(program: program, intervalMS: frameIntervalMS)
        } else if program.id.contains("pike") || program.rep?.phaseSignal == "pike_angle" {
            frames = pikeFrames(intervalMS: frameIntervalMS)
        } else if program.hold != nil || program.id.contains("plank") {
            frames = plankFrames(intervalMS: frameIntervalMS)
        } else if program.id.contains("push") || program.rep?.phaseSignal == "elbow" {
            frames = pushupFrames(program: program, intervalMS: frameIntervalMS)
        } else if program.id.contains("lunge") || program.rep?.phaseSignal.contains("knee") == true && program.id.contains("lunge") {
            frames = lungeFrames(program: program, intervalMS: frameIntervalMS)
        } else {
            frames = squatFrames(program: program, intervalMS: frameIntervalMS)
        }

        let duration = (frames.last?.timestampMS ?? 0) + frameIntervalMS
        return MotionDemoTimeline(
            programID: program.id,
            programName: program.name,
            source: .trainerReferenceFallback,
            frames: frames,
            durationMS: duration
        )
    }

    private static func squatFrames(program: ExerciseProgram, intervalMS: Int64) -> [PoseFrame] {
        let intensity = repIntensity(program: program, defaultTop: 170, defaultBottom: 90)
        let factors = [0, 0.35, 0.75, 1, 1, 1, 1, 1, 1, 1, 1, 0.75, 0.35, 0, 0, 0, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = rawFactor * intensity
            let ankleX = mix(0.65, 0.85, factor)
            let ankleY = mix(0.84, 0.64, factor)
            let shoulderY = mix(0.24, 0.30, factor)
            let wristY = mix(0.45, 0.50, factor)
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: [
                    "nose": Point3D(0.65, shoulderY - 0.12, -0.02),
                    "shoulder": Point3D(0.65, shoulderY, 0),
                    "elbow": Point3D(0.70, shoulderY + 0.12, 0.03),
                    "wrist": Point3D(0.76, wristY, 0.08),
                    "hip": Point3D(0.65, 0.44, 0),
                    "knee": Point3D(0.65, 0.64, 0.02),
                    "ankle": Point3D(ankleX, ankleY, 0.05)
                ],
                lateralOffset: 0.30
            )
        }
    }

    private static func lungeFrames(program: ExerciseProgram, intervalMS: Int64) -> [PoseFrame] {
        let intensity = repIntensity(program: program, defaultTop: 170, defaultBottom: 95)
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 1, 1, 1, 1, 0.85, 0.60, 0.35, 0.15, 0, 0, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = rawFactor * intensity
            let frontAnkle = Point3D(0.77, 0.84, 0.05)
            let shoulder = Point3D(mix(0.51, 0.52, factor), mix(0.25, 0.40, factor), 0)
            let hip = Point3D(mix(0.53, 0.53, factor), mix(0.45, 0.64, factor), 0)
            let frontKnee = Point3D(mix(0.63, 0.76, factor), mix(0.66, 0.66, factor), 0.02)
            let rearAnkle = Point3D(mix(0.35, 0.36, factor), mix(0.84, 0.815, factor), -0.18)
            let rearToe = Point3D(0.42, 0.858, -0.19)
            let rearHeel = Point3D(0.315, mix(0.850, 0.792, factor), -0.18)
            let rearKnee = Point3D(
                mix(0.39, 0.43, factor),
                mix(0.66, 0.79, factor),
                mix(-0.12, -0.16, factor)
            )
            var pose = frame(
                timestampMS: Int64(index) * intervalMS,
                primary: [
                    "nose": Point3D(mix(0.51, 0.52, factor), mix(0.13, 0.26, factor), -0.02),
                    "shoulder": shoulder,
                    "elbow": Point3D(mix(0.55, 0.56, factor), mix(0.37, 0.50, factor), 0.03),
                    "wrist": Point3D(mix(0.58, 0.58, factor), mix(0.50, 0.58, factor), 0.08),
                    "hip": hip,
                    "knee": frontKnee,
                    "ankle": frontAnkle
                ],
                lateralOffset: 0.24
            )
            var landmarks = pose.landmarks
            addNamedLandmarks(
                to: &landmarks,
                prefix: "secondary",
                points: [
                    "shoulder": Point3D(shoulder.x - 0.03, shoulder.y, -0.18),
                    "elbow": Point3D(mix(0.47, 0.48, factor), mix(0.37, 0.50, factor), -0.18),
                    "wrist": Point3D(mix(0.45, 0.46, factor), mix(0.50, 0.58, factor), -0.18),
                    "hip": Point3D(hip.x - 0.04, hip.y + 0.005, -0.18),
                    "knee": rearKnee,
                    "ankle": rearAnkle
                ]
            )
            landmarks["secondary.heel"] = landmark(rearHeel)
            landmarks["secondary.foot.index"] = landmark(rearToe)
            pose = PoseFrame(
                timestampMS: pose.timestampMS,
                imageWidth: pose.imageWidth,
                imageHeight: pose.imageHeight,
                landmarks: landmarks
            )
            return pose
        }
    }

    private static func pikeFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(mix(0.660, 0.650, factor), mix(0.390, 0.400, factor), -0.03),
                "shoulder": Point3D(mix(0.560, 0.580, factor), mix(0.480, 0.500, factor), 0),
                "elbow": Point3D(mix(0.620, 0.630, factor), mix(0.600, 0.590, factor), 0.03),
                "wrist": Point3D(0.680, 0.680, 0.08),
                "hip": Point3D(mix(0.380, 0.390, factor), mix(0.560, 0.300, factor), 0),
                "knee": Point3D(mix(0.290, 0.300, factor), mix(0.610, 0.480, factor), 0.02),
                "ankle": Point3D(0.200, 0.660, 0.04)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: 0.09
            )
        }
    }

    private static func hipFlexionFrames(program: ExerciseProgram, intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let left: [String: Point3D] = [
                "nose": Point3D(mix(0.52, 0.51, factor), mix(0.17, 0.19, factor), -0.03),
                "shoulder": Point3D(mix(0.52, 0.51, factor), mix(0.29, 0.31, factor), 0),
                "elbow": Point3D(mix(0.49, 0.48, factor), mix(0.43, 0.44, factor), 0.03),
                "wrist": Point3D(mix(0.47, 0.46, factor), mix(0.55, 0.56, factor), 0.08),
                "hip": Point3D(0.52, 0.50, 0),
                "knee": Point3D(mix(0.52, 0.70, factor), mix(0.69, 0.54, factor), 0.02),
                "ankle": Point3D(mix(0.52, 0.73, factor), mix(0.86, 0.65, factor), 0.05)
            ]
            var landmarks: [String: PoseLandmark] = [
                "nose": landmark(left["nose"]!),
                "primary.nose": landmark(left["nose"]!)
            ]
            addNamedLandmarks(to: &landmarks, prefix: "left", points: left)
            addNamedLandmarks(to: &landmarks, prefix: "primary", points: left)
            addNamedLandmarks(
                to: &landmarks,
                prefix: "right",
                points: [
                    "shoulder": Point3D(0.46, 0.30, -0.16),
                    "elbow": Point3D(0.43, 0.44, -0.16),
                    "wrist": Point3D(0.41, 0.56, -0.16),
                    "hip": Point3D(0.46, 0.50, -0.16),
                    "knee": Point3D(0.46, 0.68, -0.16),
                    "ankle": Point3D(0.46, 0.86, -0.16)
                ]
            )
            return PoseFrame(
                timestampMS: Int64(index) * intervalMS,
                imageWidth: 1280,
                imageHeight: 720,
                landmarks: landmarks
            )
        }
    }

    private static func reverseCurlFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(0.525, 0.190, -0.03),
                "shoulder": Point3D(0.520, 0.320, 0),
                "elbow": Point3D(0.490, 0.480, 0.03),
                "wrist": Point3D(mix(0.500, 0.630, factor), mix(0.720, 0.460, factor), 0.08),
                "hip": Point3D(0.520, 0.545, 0),
                "knee": Point3D(0.520, 0.710, 0.02),
                "ankle": Point3D(0.520, 0.865, 0.05)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: 0.09
            )
        }
    }

    private static func preacherCurlFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(0.495, 0.180, -0.03),
                "shoulder": Point3D(0.500, 0.300, 0),
                "elbow": Point3D(0.600, 0.540, 0.03),
                "wrist": Point3D(mix(0.680, 0.460, factor), mix(0.760, 0.500, factor), 0.08),
                "hip": Point3D(0.470, 0.590, 0),
                "knee": Point3D(0.580, 0.720, 0.02),
                "ankle": Point3D(0.630, 0.860, 0.05)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: 0.09
            )
        }
    }

    private static func chestSupportedRowFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let left: [String: Point3D] = [
                "nose": Point3D(0.430, 0.270, -0.03),
                "shoulder": Point3D(0.460, 0.400, 0),
                "elbow": Point3D(mix(0.550, 0.390, factor), mix(0.560, 0.500, factor), 0.03),
                "wrist": Point3D(mix(0.660, 0.500, factor), mix(0.730, 0.550, factor), 0.08),
                "hip": Point3D(0.580, 0.600, 0),
                "knee": Point3D(0.720, 0.710, 0.02),
                "ankle": Point3D(0.840, 0.830, 0.05)
            ]
            var landmarks: [String: PoseLandmark] = [
                "nose": landmark(left["nose"]!),
                "primary.nose": landmark(left["nose"]!)
            ]
            addNamedLandmarks(to: &landmarks, prefix: "left", points: left)
            addNamedLandmarks(to: &landmarks, prefix: "primary", points: left)
            var right: [String: Point3D] = [:]
            for (joint, point) in left where joint != "nose" {
                right[joint] = Point3D(point.x + 0.09, point.y, point.z + 0.12)
            }
            addNamedLandmarks(to: &landmarks, prefix: "right", points: right)
            return PoseFrame(
                timestampMS: Int64(index) * intervalMS,
                imageWidth: 1280,
                imageHeight: 720,
                landmarks: landmarks
            )
        }
    }

    private static func lyingTricepExtensionFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(0.300, 0.540, -0.03),
                "shoulder": Point3D(0.380, 0.550, 0),
                "elbow": Point3D(0.540, 0.380, 0.03),
                "wrist": Point3D(mix(0.700, 0.430, factor), mix(0.210, 0.310, factor), 0.08),
                "hip": Point3D(0.700, 0.600, 0),
                "knee": Point3D(0.820, 0.640, 0.02),
                "ankle": Point3D(0.920, 0.680, 0.05)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: -0.06
            )
        }
    }

    private static func cableTricepExtensionFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(0.525, 0.190, -0.03),
                "shoulder": Point3D(0.520, 0.320, 0),
                "elbow": Point3D(0.500, 0.480, 0.03),
                "wrist": Point3D(mix(0.590, 0.510, factor), mix(0.470, 0.720, factor), 0.08),
                "hip": Point3D(0.520, 0.545, 0),
                "knee": Point3D(0.520, 0.710, 0.02),
                "ankle": Point3D(0.520, 0.865, 0.05)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: 0.09
            )
        }
    }

    private static func suspensionTricepPressFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0, 0, 0.20, 0.45, 0.70, 0.90, 1, 1, 1, 0.80, 0.55, 0.30, 0.10, 0, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = smoothstep(rawFactor)
            let primary: [String: Point3D] = [
                "nose": Point3D(0.370, 0.250, -0.03),
                "shoulder": Point3D(0.420, 0.360, 0),
                "elbow": Point3D(0.510, 0.460, 0.03),
                "wrist": Point3D(mix(0.400, 0.620, factor), mix(0.490, 0.580, factor), 0.08),
                "hip": Point3D(0.620, 0.580, 0),
                "knee": Point3D(0.730, 0.700, 0.02),
                "ankle": Point3D(0.840, 0.820, 0.05)
            ]
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: primary,
                lateralOffset: 0.09
            )
        }
    }

    private static func pushupFrames(program: ExerciseProgram, intervalMS: Int64) -> [PoseFrame] {
        let intensity = repIntensity(program: program, defaultTop: 165, defaultBottom: 90)
        let factors = [0, 0, 0.20, 0.50, 0.85, 1, 1, 0.75, 0.45, 0.15, 0, 0]
        return factors.enumerated().map { index, rawFactor in
            let factor = rawFactor * intensity
            return frame(
                timestampMS: Int64(index) * intervalMS,
                primary: [
                    "nose": Point3D(mix(0.30, 0.38, factor), mix(0.34, 0.49, factor), -0.03),
                    "shoulder": Point3D(mix(0.36, 0.45, factor), mix(0.46, 0.54, factor), 0),
                    "elbow": Point3D(0.48, mix(0.58, 0.62, factor), 0.03),
                    "wrist": Point3D(0.60, 0.66, 0.08),
                    "hip": Point3D(mix(0.58, 0.64, factor), mix(0.52, 0.60, factor), 0),
                    "knee": Point3D(mix(0.72, 0.76, factor), mix(0.58, 0.66, factor), 0.02),
                    "ankle": Point3D(0.86, 0.64, 0.05)
                ],
                lateralOffset: 0.14
            )
        }
    }

    private static func plankFrames(intervalMS: Int64) -> [PoseFrame] {
        let factors = [0, 0.15, 0.30, 0.15, 0, -0.10, -0.18, -0.10, 0]
        return factors.enumerated().map { index, factor in
            frame(
                timestampMS: Int64(index) * intervalMS,
                primary: [
                    "nose": Point3D(0.30, 0.36 + (factor * 0.02), -0.03),
                    "shoulder": Point3D(0.36, 0.46 + (factor * 0.02), 0),
                    "elbow": Point3D(0.46, 0.60, 0.03),
                    "wrist": Point3D(0.54, 0.66, 0.08),
                    "hip": Point3D(0.58, 0.50 + (factor * 0.03), 0),
                    "knee": Point3D(0.72, 0.56 + (factor * 0.02), 0.02),
                    "ankle": Point3D(0.86, 0.60, 0.05)
                ],
                lateralOffset: 0.14
            )
        }
    }

    private static func repIntensity(program: ExerciseProgram, defaultTop: Double, defaultBottom: Double) -> Double {
        guard let rep = program.rep else { return 1 }
        let top = numericThreshold(in: rep.upWhen, signal: rep.phaseSignal) ?? defaultTop
        let bottom = numericThreshold(in: rep.downWhen, signal: rep.phaseSignal) ?? defaultBottom
        let rom = max(top - bottom, rep.minROMDegrees)
        return min(max(rom / 80, 1.0), 1.05)
    }

    private static func numericThreshold(in predicate: String, signal: String) -> Double? {
        let tokens = predicate.split(separator: " ").map(String.init)
        guard tokens.count == 3 else { return nil }

        if tokens[0] == signal {
            return Double(tokens[2])
        }

        if tokens[2] == signal {
            return Double(tokens[0])
        }

        return nil
    }

    private static func frame(
        timestampMS: Int64,
        primary: [String: Point3D],
        lateralOffset: Double
    ) -> PoseFrame {
        var landmarks: [String: PoseLandmark] = [:]

        for (joint, point) in primary {
            let primaryLandmark = landmark(point)
            landmarks["primary.\(joint)"] = primaryLandmark

            if joint == "nose" {
                landmarks[joint] = primaryLandmark
            } else {
                landmarks["right.\(joint)"] = landmark(Point3D(point.x, point.y, point.z + 0.10))
                landmarks["left.\(joint)"] = landmark(Point3D(point.x - lateralOffset, point.y, point.z - 0.10))
            }
        }

        if let ankle = primary["ankle"] {
            addFootLandmarks(to: &landmarks, prefix: "primary", ankle: ankle, xOffset: 0)
            addFootLandmarks(to: &landmarks, prefix: "right", ankle: Point3D(ankle.x, ankle.y, ankle.z + 0.10), xOffset: 0)
            addFootLandmarks(to: &landmarks, prefix: "left", ankle: Point3D(ankle.x - lateralOffset, ankle.y, ankle.z - 0.10), xOffset: 0)
        }

        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static func addFootLandmarks(
        to landmarks: inout [String: PoseLandmark],
        prefix: String,
        ankle: Point3D,
        xOffset: Double
    ) {
        landmarks["\(prefix).heel"] = landmark(Point3D(ankle.x - 0.045 + xOffset, ankle.y + 0.012, ankle.z))
        landmarks["\(prefix).foot.index"] = landmark(Point3D(ankle.x + 0.105 + xOffset, ankle.y + 0.018, ankle.z + 0.01))
    }

    private static func addNamedLandmarks(
        to landmarks: inout [String: PoseLandmark],
        prefix: String,
        points: [String: Point3D]
    ) {
        for (joint, point) in points {
            landmarks["\(prefix).\(joint)"] = landmark(point)
        }

        if let ankle = points["ankle"] {
            addFootLandmarks(to: &landmarks, prefix: prefix, ankle: ankle, xOffset: 0)
        }
    }

    private static func landmark(_ point: Point3D) -> PoseLandmark {
        PoseLandmark(x: point.x, y: point.y, z: point.z, visibility: 1, presence: 1)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + ((b - a) * t)
    }

    private static func smoothstep(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - (2 * clamped))
    }
}

private struct Point3D: Equatable {
    let x: Double
    let y: Double
    let z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}
