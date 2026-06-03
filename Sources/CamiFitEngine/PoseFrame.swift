import Foundation

public struct PoseFrame: Equatable {
    public let timestampMS: Int64
    public let imageWidth: Double
    public let imageHeight: Double
    public let landmarks: [String: PoseLandmark]

    public init(timestampMS: Int64, imageWidth: Double, imageHeight: Double, landmarks: [String: PoseLandmark]) {
        self.timestampMS = timestampMS
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.landmarks = landmarks
    }

    public func landmark(named reference: String) -> PoseLandmark? {
        landmarks[reference]
    }
}

public struct PoseLandmark: Equatable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let visibility: Double
    public let presence: Double

    public init(x: Double, y: Double, z: Double, visibility: Double, presence: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
        self.presence = presence
    }

    public var confidence: Double {
        min(visibility, presence)
    }
}
