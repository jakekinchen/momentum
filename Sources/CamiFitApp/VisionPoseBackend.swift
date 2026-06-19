import CamiFitEngine
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// In-process live pose backend on Apple Vision body-pose detection: no Python
/// sidecar, no model download, no IPC, no PyInstaller helper. Vision provides
/// every landmark the presets consume at runtime (shoulders, elbows, wrists,
/// hips, knees, ankles per side); frames go through the same engine naming and
/// primary-side locking as the MediaPipe worker path.
final class VisionPoseBackend: LivePoseBackend {
    var displayName: String { "Apple Vision body pose (in-process)" }
    var startFailureDiagnostics: [String] { [] }

    func start() throws {}

    func stop() {}

    func predict(imagePath: String, frameID: Int, timestampMS: Int64) throws -> PoseFrame? {
        let url = URL(fileURLWithPath: imagePath)
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])

        guard let observation = Self.primaryObservation(request.results) else {
            return nil
        }

        let size = Self.imagePixelSize(url: url)
        return VisionPoseMapping.poseFrame(
            points: Self.extractPoints(observation),
            imageWidth: size.width,
            imageHeight: size.height,
            timestampMS: timestampMS
        )
    }

    /// Mirrors the Python worker's primary-pose selection: when more than one
    /// person is detected, keep the observation with the highest mean joint
    /// confidence.
    private static func primaryObservation(
        _ observations: [VNHumanBodyPoseObservation]?
    ) -> VNHumanBodyPoseObservation? {
        guard let observations, !observations.isEmpty else { return nil }
        return observations.max { meanConfidence($0) < meanConfidence($1) }
    }

    private static func meanConfidence(_ observation: VNHumanBodyPoseObservation) -> Double {
        guard let points = try? observation.recognizedPoints(.all), !points.isEmpty else {
            return 0
        }
        return points.values.reduce(0.0) { $0 + Double($1.confidence) } / Double(points.count)
    }

    private static func extractPoints(
        _ observation: VNHumanBodyPoseObservation
    ) -> [String: VisionPoseMapping.Point] {
        guard let recognized = try? observation.recognizedPoints(.all) else { return [:] }
        var points: [String: VisionPoseMapping.Point] = [:]

        for (rawName, jointName) in VisionPoseMapping.visionJointsByRawName {
            guard let point = recognized[jointName] else { continue }
            points[rawName] = VisionPoseMapping.Point(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }

        return points
    }

    private static func imagePixelSize(url: URL) -> (width: Double, height: Double) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else {
            return (width: 1280, height: 720)
        }
        return (width: width, height: height)
    }
}

/// Pure conversion from Vision body-pose points to an engine `PoseFrame`,
/// kept free of Vision observation types so it is unit-testable. Vision
/// reports normalized points with a bottom-left origin; engine pose frames
/// use image space with a top-left origin, so y is flipped.
enum VisionPoseMapping {
    struct Point {
        let x: Double
        let y: Double
        let confidence: Double
    }

    /// Vision joints keyed by the MediaPipe-style raw landmark name the engine
    /// mapping expects. Joints MediaPipe defines but Vision does not provide
    /// (eye inner/outer, mouth, fingers, heel, foot index) are simply absent
    /// from live frames; no preset references them at runtime.
    static let visionJointsByRawName: [String: VNHumanBodyPoseObservation.JointName] = [
        "nose": .nose,
        "left_eye": .leftEye,
        "right_eye": .rightEye,
        "left_ear": .leftEar,
        "right_ear": .rightEar,
        "left_shoulder": .leftShoulder,
        "right_shoulder": .rightShoulder,
        "left_elbow": .leftElbow,
        "right_elbow": .rightElbow,
        "left_wrist": .leftWrist,
        "right_wrist": .rightWrist,
        "left_hip": .leftHip,
        "right_hip": .rightHip,
        "left_knee": .leftKnee,
        "right_knee": .rightKnee,
        "left_ankle": .leftAnkle,
        "right_ankle": .rightAnkle
    ]

    static func poseFrame(
        points: [String: Point],
        imageWidth: Double,
        imageHeight: Double,
        timestampMS: Int64
    ) -> PoseFrame? {
        var byRawName: [String: PoseLandmark] = [:]
        byRawName.reserveCapacity(points.count)

        for (rawName, point) in points where point.confidence > 0 {
            byRawName[rawName] = PoseLandmark(
                x: point.x,
                y: 1.0 - point.y,
                z: 0,
                visibility: point.confidence,
                presence: point.confidence
            )
        }

        return MediaPipePoseJSONLDecoder.livePoseFrame(
            timestampMS: timestampMS,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            landmarksByRawName: byRawName
        )
    }
}
