import Foundation

public protocol PoseProvider {
    func frames() throws -> [PoseFrame]
}

public struct MediaPipePoseProvider: PoseProvider {
    private let jsonlURL: URL

    public init(jsonlURL: URL) {
        self.jsonlURL = jsonlURL
    }

    public func frames() throws -> [PoseFrame] {
        try MediaPipePoseJSONLDecoder.decode(contentsOf: jsonlURL)
    }
}

public enum MediaPipePoseJSONLDecoder {
    public static let landmarkNames = [
        "nose",
        "left_eye_inner",
        "left_eye",
        "left_eye_outer",
        "right_eye_inner",
        "right_eye",
        "right_eye_outer",
        "left_ear",
        "right_ear",
        "mouth_left",
        "mouth_right",
        "left_shoulder",
        "right_shoulder",
        "left_elbow",
        "right_elbow",
        "left_wrist",
        "right_wrist",
        "left_pinky",
        "right_pinky",
        "left_index",
        "right_index",
        "left_thumb",
        "right_thumb",
        "left_hip",
        "right_hip",
        "left_knee",
        "right_knee",
        "left_ankle",
        "right_ankle",
        "left_heel",
        "right_heel",
        "left_foot_index",
        "right_foot_index"
    ]

    private static let requiredPrimaryJoints = ["shoulder", "hip", "knee", "ankle"]

    public static func decode(contentsOf url: URL) throws -> [PoseFrame] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try decode(jsonl: contents)
    }

    public static func decode(jsonl: String) throws -> [PoseFrame] {
        var frames: [PoseFrame] = []
        let lines = jsonl.split(whereSeparator: \.isNewline)

        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            guard let data = String(line).data(using: .utf8) else {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "line is not utf8")
            }

            let raw: RawPoseRecord
            do {
                raw = try JSONDecoder().decode(RawPoseRecord.self, from: data)
            } catch {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "malformed JSON: \(error)")
            }

            guard raw.type == "pose" else {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "expected type 'pose'")
            }

            guard raw.imageSize.count == 2 else {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "image_size must contain width and height")
            }

            if raw.posesDetected == 0 {
                guard raw.primaryPoseID == nil else {
                    throw MediaPipePoseDecodeError.invalidLine(lineNumber, "no-pose record must have null primary_pose_id")
                }

                guard raw.landmarks.isEmpty && raw.worldLandmarks.isEmpty else {
                    throw MediaPipePoseDecodeError.invalidLine(lineNumber, "no-pose record must have empty landmarks and world_landmarks")
                }

                frames.append(
                    PoseFrame(
                        timestampMS: raw.timestampMS,
                        imageWidth: raw.imageSize[0],
                        imageHeight: raw.imageSize[1],
                        landmarks: [:]
                    )
                )
                continue
            }

            guard raw.posesDetected > 0 else {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "poses_detected must be non-negative")
            }

            guard raw.landmarks.count == landmarkNames.count else {
                throw MediaPipePoseDecodeError.invalidLine(
                    lineNumber,
                    "expected \(landmarkNames.count) landmarks, got \(raw.landmarks.count)"
                )
            }

            frames.append(
                PoseFrame(
                    timestampMS: raw.timestampMS,
                    imageWidth: raw.imageSize[0],
                    imageHeight: raw.imageSize[1],
                    landmarks: try mappedLandmarks(raw.landmarks, lineNumber: lineNumber)
                )
            )
        }

        return frames
    }

    private static func mappedLandmarks(_ rawLandmarks: [RawMediaPipeLandmark], lineNumber: Int) throws -> [String: PoseLandmark] {
        var mapped: [String: PoseLandmark] = [:]

        for (index, name) in landmarkNames.enumerated() {
            let raw = rawLandmarks[index]
            let engineName = name.replacingOccurrences(of: "_", with: ".")
            mapped[engineName] = PoseLandmark(
                x: raw.x,
                y: raw.y,
                z: raw.z,
                visibility: raw.visibility,
                presence: raw.presence ?? raw.visibility
            )
        }

        let primarySide = strongestSide(in: mapped)
        for joint in requiredPrimaryJoints {
            guard let landmark = mapped["\(primarySide).\(joint)"] else {
                throw MediaPipePoseDecodeError.invalidLine(lineNumber, "missing required \(primarySide).\(joint) landmark")
            }
            mapped["primary.\(joint)"] = landmark
        }

        return mapped
    }

    private static func strongestSide(in landmarks: [String: PoseLandmark]) -> String {
        func score(_ side: String) -> Double {
            let values = requiredPrimaryJoints.compactMap { landmarks["\(side).\($0)"]?.confidence }
            guard !values.isEmpty else {
                return -Double.infinity
            }
            return values.reduce(0, +) / Double(values.count)
        }

        return score("right") >= score("left") ? "right" : "left"
    }
}

public enum MediaPipePoseDecodeError: Error, Equatable, CustomStringConvertible {
    case invalidLine(Int, String)

    public var description: String {
        switch self {
        case let .invalidLine(line, reason):
            return "invalid MediaPipe pose JSONL line \(line): \(reason)"
        }
    }
}

private struct RawPoseRecord: Decodable {
    let type: String
    let timestampMS: Int64
    let imageSize: [Double]
    let posesDetected: Int
    let primaryPoseID: String?
    let landmarks: [RawMediaPipeLandmark]
    let worldLandmarks: [RawWorldLandmark]

    private enum CodingKeys: String, CodingKey {
        case type
        case timestampMS = "timestamp_ms"
        case imageSize = "image_size"
        case posesDetected = "poses_detected"
        case primaryPoseID = "primary_pose_id"
        case landmarks
        case worldLandmarks = "world_landmarks"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        timestampMS = try container.decode(Int64.self, forKey: .timestampMS)
        imageSize = try container.decode([Double].self, forKey: .imageSize)
        posesDetected = try container.decode(Int.self, forKey: .posesDetected)
        landmarks = try container.decode([RawMediaPipeLandmark].self, forKey: .landmarks)
        worldLandmarks = try container.decode([RawWorldLandmark].self, forKey: .worldLandmarks)

        if let id = try? container.decode(String.self, forKey: .primaryPoseID) {
            primaryPoseID = id
        } else if let id = try? container.decode(Int.self, forKey: .primaryPoseID) {
            primaryPoseID = String(id)
        } else {
            primaryPoseID = nil
        }
    }
}

private struct RawMediaPipeLandmark: Decodable {
    let x: Double
    let y: Double
    let z: Double
    let visibility: Double
    let presence: Double?
}

private struct RawWorldLandmark: Decodable {
    let x: Double
    let y: Double
    let z: Double
}
