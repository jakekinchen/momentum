import XCTest
@testable import CamiFitApp

final class PoseOverlayViewTests: XCTestCase {
    func testNormalizedOverlayPointMapsIntoViewportCoordinates() {
        let state = AppPoseOverlayState(
            timestampMS: 1_000,
            points: [
                AppPoseOverlayState.Point(id: "primary.knee", x: 0.65, y: 0.64, confidence: 0.96)
            ],
            segments: []
        )

        let drawables = PoseOverlayGeometryMapper.map(
            state,
            viewport: PoseOverlayViewport(width: 200, height: 100)
        )

        XCTAssertEqual(drawables.points, [
            PoseOverlayMappedPoint(id: "primary.knee", x: 130, y: 64, confidence: 0.96)
        ])
        XCTAssertEqual(drawables.segments, [])

        print("pose-overlay-map-point id=primary.knee viewport=200x100 mapped=(130.0,64.0) confidence=0.96")
    }

    func testOverlaySegmentsMapOnlyWhenEndpointsExist() {
        let state = AppPoseOverlayState(
            timestampMS: 1_000,
            points: [
                AppPoseOverlayState.Point(id: "primary.hip", x: 0.5, y: 0.4, confidence: 0.97),
                AppPoseOverlayState.Point(id: "primary.knee", x: 0.5, y: 0.7, confidence: 0.96)
            ],
            segments: [
                AppPoseOverlayState.Segment(id: "primary.hip->primary.knee", fromID: "primary.hip", toID: "primary.knee"),
                AppPoseOverlayState.Segment(id: "primary.knee->primary.ankle", fromID: "primary.knee", toID: "primary.ankle")
            ]
        )

        let drawables = PoseOverlayGeometryMapper.map(
            state,
            viewport: PoseOverlayViewport(width: 300, height: 200)
        )

        XCTAssertEqual(drawables.points.count, 2)
        XCTAssertEqual(drawables.segments, [
            PoseOverlayMappedSegment(
                id: "primary.hip->primary.knee",
                from: PoseOverlayMappedPoint(id: "primary.hip", x: 150, y: 80, confidence: 0.97),
                to: PoseOverlayMappedPoint(id: "primary.knee", x: 150, y: 140, confidence: 0.96)
            )
        ])

        print("pose-overlay-map-segments viewport=300x200 points=2 segments=1 omitted_missing_endpoint=true")
    }

    func testEmptyOverlayStateMapsToNoDrawables() {
        let drawables = PoseOverlayGeometryMapper.map(
            .empty,
            viewport: PoseOverlayViewport(width: 200, height: 100)
        )

        XCTAssertEqual(drawables.points, [])
        XCTAssertEqual(drawables.segments, [])

        print("pose-overlay-empty viewport=200x100 points=0 segments=0")
    }

    func testCleanRecordedRunOverlayStateFeedsGeometryMapper() throws {
        let viewModel = AppExerciseSessionViewModel()

        _ = viewModel.runRecordedRun(id: "squat_two_frames")
        let overlay = viewModel.latestPoseOverlayState
        let drawables = PoseOverlayGeometryMapper.map(
            overlay,
            viewport: PoseOverlayViewport(width: 200, height: 100)
        )
        let primaryKnee = try XCTUnwrap(drawables.points.first { $0.id == "primary.knee" })

        XCTAssertEqual(drawables.points.count, 12)
        XCTAssertEqual(drawables.segments.count, 9)
        XCTAssertEqual(primaryKnee.x, 130, accuracy: 0.000_001)
        XCTAssertEqual(primaryKnee.y, 64, accuracy: 0.000_001)

        print(
            "pose-overlay-recorded-run run=squat_two_frames viewport=200x100 " +
            "points=\(drawables.points.count) segments=\(drawables.segments.count) primary_knee=(\(primaryKnee.x),\(primaryKnee.y))"
        )
    }
}
