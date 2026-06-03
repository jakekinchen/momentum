import Foundation
@testable import CamiFitEngine

struct PoseFrameFixture {
    let id: String
    let frames: [PoseFrame]
}

enum PoseFrameFixtureLoader {
    static func load(from url: URL) throws -> PoseFrameFixture {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(RawPoseFrameFixture.self, from: data)
        return PoseFrameFixture(
            id: raw.id,
            frames: raw.frames.map { frame in
                PoseFrame(
                    timestampMS: frame.timestampMS,
                    imageWidth: raw.imageWidth,
                    imageHeight: raw.imageHeight,
                    landmarks: frame.landmarks.mapValues { landmark in
                        PoseLandmark(
                            x: landmark.x,
                            y: landmark.y,
                            z: landmark.z,
                            visibility: landmark.visibility,
                            presence: landmark.presence
                        )
                    }
                )
            }
        )
    }
}

private struct RawPoseFrameFixture: Decodable {
    let id: String
    let imageWidth: Double
    let imageHeight: Double
    let frames: [RawPoseFrame]

    private enum CodingKeys: String, CodingKey {
        case id
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case frames
    }
}

private struct RawPoseFrame: Decodable {
    let timestampMS: Int64
    let landmarks: [String: RawPoseLandmark]

    private enum CodingKeys: String, CodingKey {
        case timestampMS = "timestamp_ms"
        case landmarks
    }
}

private struct RawPoseLandmark: Decodable {
    let x: Double
    let y: Double
    let z: Double
    let visibility: Double
    let presence: Double
}
