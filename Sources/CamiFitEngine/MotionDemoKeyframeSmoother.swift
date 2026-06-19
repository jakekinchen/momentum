import Foundation

/// Zero-lag keyframe smoothing for recorded guide motion traces.
///
/// Recorded traces preserve per-frame MediaPipe estimation noise; on slow
/// guide cycles that noise exceeds the true per-frame motion and the avatar
/// reads as jittery. Each pass replaces every interior keyframe with a
/// symmetric binomial blend ([1,2,1]/4) of its neighbors, which removes
/// high-frequency wiggle without phase lag.
///
/// Invariants the avatar pipeline relies on:
/// - Contact-anchored landmarks are constant across frames, and a weighted
///   average of identical values is that value — anchors do not drift.
/// - The first and last frames are never modified, so loop closure (the
///   duplicated final frame) and anchor positions at the loop boundary hold
///   exactly.
/// - Timestamps, frame count, image size, and visibility/presence are
///   untouched; only landmark x/y/z move.
public enum MotionDemoKeyframeSmoother {
    public static let defaultPasses = 2

    public static func smooth(_ frames: [PoseFrame], passes: Int = defaultPasses) -> [PoseFrame] {
        guard passes > 0, frames.count >= 3 else { return frames }

        var current = frames
        for _ in 0..<passes {
            current = singlePass(current)
        }
        return current
    }

    private static func singlePass(_ frames: [PoseFrame]) -> [PoseFrame] {
        var smoothed = frames

        for index in 1..<(frames.count - 1) {
            let previous = frames[index - 1].landmarks
            let frame = frames[index]
            let next = frames[index + 1].landmarks
            var landmarks = frame.landmarks

            for (name, landmark) in frame.landmarks {
                guard let before = previous[name], let after = next[name] else {
                    continue
                }

                landmarks[name] = PoseLandmark(
                    x: blend(before.x, landmark.x, after.x),
                    y: blend(before.y, landmark.y, after.y),
                    z: blend(before.z, landmark.z, after.z),
                    visibility: landmark.visibility,
                    presence: landmark.presence
                )
            }

            smoothed[index] = PoseFrame(
                timestampMS: frame.timestampMS,
                imageWidth: frame.imageWidth,
                imageHeight: frame.imageHeight,
                landmarks: landmarks
            )
        }

        return smoothed
    }

    private static func blend(_ before: Double, _ current: Double, _ after: Double) -> Double {
        (before + (2 * current) + after) / 4
    }
}
