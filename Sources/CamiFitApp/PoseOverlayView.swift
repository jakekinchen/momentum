import SwiftUI

public struct PoseOverlayViewport: Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PoseOverlayMappedPoint: Equatable, Identifiable {
    public let id: String
    public let x: Double
    public let y: Double
    public let confidence: Double
}

public struct PoseOverlayMappedSegment: Equatable, Identifiable {
    public let id: String
    public let from: PoseOverlayMappedPoint
    public let to: PoseOverlayMappedPoint
}

public struct PoseOverlayDrawables: Equatable {
    public let points: [PoseOverlayMappedPoint]
    public let segments: [PoseOverlayMappedSegment]
}

public enum PoseOverlayGeometryMapper {
    public static func map(_ state: AppPoseOverlayState, viewport: PoseOverlayViewport) -> PoseOverlayDrawables {
        guard viewport.width > 0, viewport.height > 0 else {
            return PoseOverlayDrawables(points: [], segments: [])
        }

        let points = state.points.map { point in
            PoseOverlayMappedPoint(
                id: point.id,
                x: point.x * viewport.width,
                y: point.y * viewport.height,
                confidence: point.confidence
            )
        }

        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        let segments = state.segments.compactMap { segment -> PoseOverlayMappedSegment? in
            guard let from = pointsByID[segment.fromID],
                  let to = pointsByID[segment.toID] else {
                return nil
            }

            return PoseOverlayMappedSegment(id: segment.id, from: from, to: to)
        }

        return PoseOverlayDrawables(points: points, segments: segments)
    }
}

struct PoseOverlayView: View {
    let state: AppPoseOverlayState

    var body: some View {
        GeometryReader { proxy in
            let drawables = PoseOverlayGeometryMapper.map(
                state,
                viewport: PoseOverlayViewport(width: Double(proxy.size.width), height: Double(proxy.size.height))
            )

            Canvas { context, _ in
                for segment in drawables.segments {
                    var path = Path()
                    path.move(to: CGPoint(x: segment.from.x, y: segment.from.y))
                    path.addLine(to: CGPoint(x: segment.to.x, y: segment.to.y))
                    context.stroke(path, with: .color(.cyan), lineWidth: 2)
                }

                for point in drawables.points {
                    let radius = 3.0 + (point.confidence * 2.0)
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.yellow))
                }
            }
        }
    }
}
