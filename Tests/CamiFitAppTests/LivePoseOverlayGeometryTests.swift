import XCTest
@testable import CamiFitApp

final class LivePoseOverlayGeometryTests: XCTestCase {
    func testMirroringFlipsLiveOverlayXWithoutChangingY() {
        let point = AppPoseOverlayState.Point(id: "primary.wrist", x: 0.25, y: 0.40, confidence: 0.90)
        let viewport = CGSize(width: 1000, height: 500)
        let source = CGSize(width: 1000, height: 500)

        let unmirrored = LivePoseOverlayGeometryMapper.map(
            point: point,
            viewportSize: viewport,
            sourceSize: source,
            mirrored: false
        )
        let mirrored = LivePoseOverlayGeometryMapper.map(
            point: point,
            viewportSize: viewport,
            sourceSize: source,
            mirrored: true
        )

        XCTAssertEqual(unmirrored.x, 250, accuracy: 0.001)
        XCTAssertEqual(mirrored.x, 750, accuracy: 0.001)
        XCTAssertEqual(unmirrored.y, mirrored.y, accuracy: 0.001)
    }

    func testMirroringUsesAspectFillMappedCoordinate() {
        let point = AppPoseOverlayState.Point(id: "primary.hip", x: 0.25, y: 0.50, confidence: 0.90)
        let viewport = CGSize(width: 800, height: 600)
        let source = CGSize(width: 640, height: 360)

        let unmirrored = LivePoseOverlayGeometryMapper.map(
            point: point,
            viewportSize: viewport,
            sourceSize: source,
            mirrored: false
        )
        let mirrored = LivePoseOverlayGeometryMapper.map(
            point: point,
            viewportSize: viewport,
            sourceSize: source,
            mirrored: true
        )

        XCTAssertEqual(unmirrored.x, 133.333, accuracy: 0.001)
        XCTAssertEqual(mirrored.x, 666.667, accuracy: 0.001)
        XCTAssertEqual(unmirrored.y, 300, accuracy: 0.001)
        XCTAssertEqual(mirrored.y, 300, accuracy: 0.001)
    }
}
