import CamiFitEngine
import Foundation

public struct AppPoseOverlayState: Equatable {
    public struct Point: Equatable, Identifiable {
        public let id: String
        public let x: Double
        public let y: Double
        public let confidence: Double
    }

    public struct Segment: Equatable, Identifiable {
        public let id: String
        public let fromID: String
        public let toID: String
    }

    public let timestampMS: Int64?
    public let points: [Point]
    public let segments: [Segment]

    public static let empty = AppPoseOverlayState(timestampMS: nil, points: [], segments: [])

    public init(timestampMS: Int64?, points: [Point], segments: [Segment]) {
        self.timestampMS = timestampMS
        self.points = points
        self.segments = segments
    }

    public init(frame: PoseFrame, minimumConfidence: Double = 0.65) {
        let points = frame.landmarks
            .compactMap { name, landmark -> Point? in
                guard landmark.confidence >= minimumConfidence,
                      landmark.x.isFinite,
                      landmark.y.isFinite,
                      (0 ... 1).contains(landmark.x),
                      (0 ... 1).contains(landmark.y) else {
                    return nil
                }

                return Point(id: name, x: landmark.x, y: landmark.y, confidence: landmark.confidence)
            }
            .sorted { $0.id < $1.id }

        let pointIDs = Set(points.map(\.id))
        let segments = Self.segmentDefinitions.compactMap { fromID, toID -> Segment? in
            guard pointIDs.contains(fromID), pointIDs.contains(toID) else {
                return nil
            }

            return Segment(id: "\(fromID)->\(toID)", fromID: fromID, toID: toID)
        }

        self.init(timestampMS: frame.timestampMS, points: points, segments: segments)
    }

    private static let segmentDefinitions = [
        ("primary.shoulder", "primary.hip"),
        ("primary.hip", "primary.knee"),
        ("primary.knee", "primary.ankle"),
        ("left.shoulder", "right.shoulder"),
        ("left.hip", "right.hip"),
        ("left.shoulder", "left.elbow"),
        ("left.elbow", "left.wrist"),
        ("right.shoulder", "right.elbow"),
        ("right.elbow", "right.wrist"),
        ("left.hip", "left.knee"),
        ("left.knee", "left.ankle"),
        ("right.hip", "right.knee"),
        ("right.knee", "right.ankle")
    ]
}
