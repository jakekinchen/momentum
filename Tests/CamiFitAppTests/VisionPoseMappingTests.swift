import XCTest
import CamiFitEngine
@testable import CamiFitApp

final class VisionPoseMappingTests: XCTestCase {
    private func fullBodyPoints(
        confidence: Double = 0.9,
        rightConfidence: Double? = nil
    ) -> [String: VisionPoseMapping.Point] {
        var points: [String: VisionPoseMapping.Point] = [
            "nose": .init(x: 0.50, y: 0.90, confidence: confidence)
        ]
        let joints: [(String, Double, Double)] = [
            ("shoulder", 0.45, 0.75),
            ("elbow", 0.42, 0.60),
            ("wrist", 0.40, 0.45),
            ("hip", 0.50, 0.50),
            ("knee", 0.50, 0.30),
            ("ankle", 0.50, 0.10)
        ]
        for (joint, x, y) in joints {
            points["left_\(joint)"] = .init(x: x - 0.05, y: y, confidence: confidence)
            points["right_\(joint)"] = .init(x: x + 0.05, y: y, confidence: rightConfidence ?? confidence)
        }
        return points
    }

    func testFlipsVisionYIntoImageSpace() throws {
        let frame = try XCTUnwrap(VisionPoseMapping.poseFrame(
            points: fullBodyPoints(),
            imageWidth: 360,
            imageHeight: 640,
            timestampMS: 42
        ))

        let ankle = try XCTUnwrap(frame.landmark(named: "left.ankle"))
        XCTAssertEqual(ankle.y, 0.9, accuracy: 0.000_001, "Vision y=0.1 (bottom-left origin) is image y=0.9")
        let nose = try XCTUnwrap(frame.landmark(named: "nose"))
        XCTAssertEqual(nose.y, 0.1, accuracy: 0.000_001)
        XCTAssertLessThan(nose.y, ankle.y, "head should sit above ankles in image space")
        XCTAssertEqual(frame.timestampMS, 42)
        XCTAssertEqual(frame.imageWidth, 360)
        XCTAssertEqual(frame.imageHeight, 640)
    }

    func testMapsRawNamesAndLocksPrimarySide() throws {
        let frame = try XCTUnwrap(VisionPoseMapping.poseFrame(
            points: fullBodyPoints(confidence: 0.5, rightConfidence: 0.95),
            imageWidth: 360,
            imageHeight: 640,
            timestampMS: 0
        ))

        XCTAssertNotNil(frame.landmark(named: "left.shoulder"))
        XCTAssertNotNil(frame.landmark(named: "right.elbow"))
        let primaryHip = try XCTUnwrap(frame.landmark(named: "primary.hip"))
        let rightHip = try XCTUnwrap(frame.landmark(named: "right.hip"))
        XCTAssertEqual(primaryHip.x, rightHip.x, "primary should lock to the higher-confidence right side")
        XCTAssertEqual(primaryHip.visibility, 0.95)
        XCTAssertEqual(primaryHip.presence, 0.95)
    }

    func testDropsZeroConfidencePoints() throws {
        var points = fullBodyPoints()
        points["left_ear"] = .init(x: 0.4, y: 0.9, confidence: 0)

        let frame = try XCTUnwrap(VisionPoseMapping.poseFrame(
            points: points,
            imageWidth: 360,
            imageHeight: 640,
            timestampMS: 0
        ))

        XCTAssertNil(frame.landmark(named: "left.ear"), "undetected joints must not enter the frame")
    }

    func testReturnsNilWithoutRequiredJoints() {
        var points = fullBodyPoints()
        points["left_ankle"] = nil
        points["right_ankle"] = nil

        XCTAssertNil(VisionPoseMapping.poseFrame(
            points: points,
            imageWidth: 360,
            imageHeight: 640,
            timestampMS: 0
        ), "a pose without ankles on the locked side is not usable")
    }
}
