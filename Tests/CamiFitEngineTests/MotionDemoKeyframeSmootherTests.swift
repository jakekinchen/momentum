import XCTest
@testable import CamiFitEngine

final class MotionDemoKeyframeSmootherTests: XCTestCase {
    func testConstantAnchoredLandmarksDoNotDrift() {
        let frames = (0..<20).map { index in
            Self.frame(
                timestampMS: Int64(index) * 67,
                landmarks: [
                    "primary.heel": Self.landmark(x: 0.81, y: 0.84),
                    "primary.knee": Self.landmark(x: 0.5 + Double(index % 2) * 0.01, y: 0.6)
                ]
            )
        }

        let smoothed = MotionDemoKeyframeSmoother.smooth(frames)

        for (index, frame) in smoothed.enumerated() {
            let heel = frame.landmark(named: "primary.heel")!
            XCTAssertEqual(heel.x, 0.81, accuracy: 0.000_000_1, "anchored heel drifted at frame \(index)")
            XCTAssertEqual(heel.y, 0.84, accuracy: 0.000_000_1, "anchored heel drifted at frame \(index)")
        }
    }

    func testReducesAlternatingNoiseOnMovingLandmark() {
        // A slow ramp with ±0.01 alternating noise — the jitter signature.
        let frames = (0..<30).map { index in
            let noise = index.isMultiple(of: 2) ? 0.01 : -0.01
            return Self.frame(
                timestampMS: Int64(index) * 67,
                landmarks: ["primary.knee": Self.landmark(x: 0.4 + Double(index) * 0.002 + noise, y: 0.6)]
            )
        }

        func meanAcceleration(_ frames: [PoseFrame]) -> Double {
            var values: [Double] = []
            for index in 1..<(frames.count - 1) {
                let a = frames[index - 1].landmark(named: "primary.knee")!.x
                let b = frames[index].landmark(named: "primary.knee")!.x
                let c = frames[index + 1].landmark(named: "primary.knee")!.x
                values.append(abs(c - 2 * b + a))
            }
            return values.reduce(0, +) / Double(values.count)
        }

        let smoothed = MotionDemoKeyframeSmoother.smooth(frames)

        XCTAssertLessThan(
            meanAcceleration(smoothed),
            meanAcceleration(frames) / 4,
            "two binomial passes should cut alternating noise by well over 4x"
        )
    }

    func testFirstAndLastFramesAreUntouched() {
        let frames = (0..<10).map { index in
            Self.frame(
                timestampMS: Int64(index) * 67,
                landmarks: ["primary.knee": Self.landmark(x: Double(index) * 0.05, y: 0.5)]
            )
        }

        let smoothed = MotionDemoKeyframeSmoother.smooth(frames)

        XCTAssertEqual(smoothed.first, frames.first, "loop-closure frame must stay byte-identical")
        XCTAssertEqual(smoothed.last, frames.last, "loop-closure frame must stay byte-identical")
    }

    func testPreservesTimestampsCountAndMetadata() {
        let frames = (0..<8).map { index in
            Self.frame(
                timestampMS: Int64(index) * 67 + 5,
                landmarks: ["primary.knee": Self.landmark(x: Double(index) * 0.1, y: 0.5, visibility: 0.7)]
            )
        }

        let smoothed = MotionDemoKeyframeSmoother.smooth(frames)

        XCTAssertEqual(smoothed.count, frames.count)
        for (original, result) in zip(frames, smoothed) {
            XCTAssertEqual(result.timestampMS, original.timestampMS)
            XCTAssertEqual(result.imageWidth, original.imageWidth)
            XCTAssertEqual(result.imageHeight, original.imageHeight)
            XCTAssertEqual(result.landmark(named: "primary.knee")?.visibility, 0.7)
        }
    }

    func testLandmarkMissingFromNeighborIsLeftUnchanged() {
        var frames = (0..<5).map { index in
            Self.frame(
                timestampMS: Int64(index) * 67,
                landmarks: ["primary.knee": Self.landmark(x: Double(index) * 0.1, y: 0.5)]
            )
        }
        frames[2] = Self.frame(
            timestampMS: frames[2].timestampMS,
            landmarks: [
                "primary.knee": Self.landmark(x: 0.2, y: 0.5),
                "primary.wrist": Self.landmark(x: 0.9, y: 0.3)
            ]
        )

        let smoothed = MotionDemoKeyframeSmoother.smooth(frames, passes: 1)

        XCTAssertEqual(smoothed[2].landmark(named: "primary.wrist")?.x, 0.9, "no neighbors to blend with")
    }

    func testShortOrZeroPassInputsPassThrough() {
        let twoFrames = (0..<2).map { index in
            Self.frame(timestampMS: Int64(index), landmarks: ["primary.knee": Self.landmark(x: 0.1, y: 0.1)])
        }

        XCTAssertEqual(MotionDemoKeyframeSmoother.smooth(twoFrames), twoFrames)
        XCTAssertEqual(MotionDemoKeyframeSmoother.smooth(twoFrames, passes: 0), twoFrames)
    }

    private static func frame(timestampMS: Int64, landmarks: [String: PoseLandmark]) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static func landmark(x: Double, y: Double, visibility: Double = 1) -> PoseLandmark {
        PoseLandmark(x: x, y: y, z: 0, visibility: visibility, presence: visibility)
    }
}
