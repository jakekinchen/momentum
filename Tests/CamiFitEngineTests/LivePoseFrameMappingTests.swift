import XCTest
@testable import CamiFitEngine

final class LivePoseFrameMappingTests: XCTestCase {
    func testLivePoseFrameMatchesWorkerJSONLDecodePath() throws {
        var orderedLandmarks: [[String: Double]] = []
        var byRawName: [String: PoseLandmark] = [:]

        for (index, name) in MediaPipePoseJSONLDecoder.landmarkNames.enumerated() {
            let value = Double(index)
            let landmark: [String: Double] = [
                "x": 0.01 * value,
                "y": 0.02 * value,
                "z": 0.001 * value,
                "visibility": 0.9,
                "presence": 0.8
            ]
            orderedLandmarks.append(landmark)
            byRawName[name] = PoseLandmark(
                x: landmark["x"]!,
                y: landmark["y"]!,
                z: landmark["z"]!,
                visibility: landmark["visibility"]!,
                presence: landmark["presence"]!
            )
        }

        let record: [String: Any] = [
            "type": "pose",
            "timestamp_ms": 1_234,
            "image_size": [640.0, 480.0],
            "poses_detected": 1,
            "primary_pose_id": "0",
            "landmarks": orderedLandmarks,
            "world_landmarks": orderedLandmarks.map { ["x": $0["x"]!, "y": $0["y"]!, "z": $0["z"]!] }
        ]
        let jsonl = String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        let decoded = try XCTUnwrap(MediaPipePoseJSONLDecoder.decode(jsonl: jsonl).first)

        let live = try XCTUnwrap(MediaPipePoseJSONLDecoder.livePoseFrame(
            timestampMS: 1_234,
            imageWidth: 640,
            imageHeight: 480,
            landmarksByRawName: byRawName
        ))

        XCTAssertEqual(live.timestampMS, decoded.timestampMS)
        XCTAssertEqual(live.imageWidth, decoded.imageWidth)
        XCTAssertEqual(live.imageHeight, decoded.imageHeight)
        XCTAssertEqual(live.landmarks, decoded.landmarks)
        XCTAssertNotNil(live.landmark(named: "primary.shoulder"))
        XCTAssertNotNil(live.landmark(named: "primary.ankle"))
    }

    func testLivePoseFrameLocksPrimaryToStrongestSide() throws {
        var byRawName: [String: PoseLandmark] = [:]
        for joint in ["shoulder", "hip", "knee", "ankle"] {
            byRawName["left_\(joint)"] = PoseLandmark(x: 0.2, y: 0.5, z: 0, visibility: 0.95, presence: 0.95)
            byRawName["right_\(joint)"] = PoseLandmark(x: 0.8, y: 0.5, z: 0, visibility: 0.40, presence: 0.40)
        }

        let frame = try XCTUnwrap(MediaPipePoseJSONLDecoder.livePoseFrame(
            timestampMS: 0,
            imageWidth: 640,
            imageHeight: 480,
            landmarksByRawName: byRawName
        ))

        let primaryShoulder = try XCTUnwrap(frame.landmark(named: "primary.shoulder"))
        XCTAssertEqual(primaryShoulder.x, 0.2, "primary should lock to the higher-confidence left side")
        XCTAssertEqual(frame.landmark(named: "left.knee")?.x, 0.2)
        XCTAssertEqual(frame.landmark(named: "right.knee")?.x, 0.8)
    }

    func testLivePoseFrameReturnsNilWhenRequiredJointMissing() {
        var byRawName: [String: PoseLandmark] = [:]
        for joint in ["shoulder", "hip", "knee"] {
            byRawName["left_\(joint)"] = PoseLandmark(x: 0.5, y: 0.5, z: 0, visibility: 0.9, presence: 0.9)
            byRawName["right_\(joint)"] = PoseLandmark(x: 0.5, y: 0.5, z: 0, visibility: 0.9, presence: 0.9)
        }

        XCTAssertNil(MediaPipePoseJSONLDecoder.livePoseFrame(
            timestampMS: 0,
            imageWidth: 640,
            imageHeight: 480,
            landmarksByRawName: byRawName
        ), "no ankle on either side means no usable pose")
    }
}
