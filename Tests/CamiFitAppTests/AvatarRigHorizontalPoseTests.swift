import AppKit
import SceneKit
import XCTest
import CamiFitEngine
@testable import CamiFitApp

/// Structural invariants for the mannequin rig on horizontal poses (plank,
/// pike). These encode the 2026-06-09 installed-app review failures —
/// "detached head/neck and broken forearm/torso attachment" — as geometry
/// assertions so the rig cannot silently regress, and double as the
/// review-evidence renderer for horizontal-pose candidates.
final class AvatarRigHorizontalPoseTests: XCTestCase {
    func testPlankFramesKeepHeadNeckAndForearmsAttached() throws {
        try assertRigAttachmentInvariants(exerciseID: "bodyweight_plank")
    }

    func testPikeFramesKeepHeadNeckAndForearmsAttached() throws {
        try assertRigAttachmentInvariants(exerciseID: "bodyweight_pike")
    }

    func testSquatControlKeepsHeadNeckAndForearmsAttached() throws {
        try assertRigAttachmentInvariants(exerciseID: "bodyweight_squat")
    }

    // MARK: - Invariants

    private func assertRigAttachmentInvariants(exerciseID: String) throws {
        let frames = try Self.bundledFrames(exerciseID)
        XCTAssertFalse(frames.isEmpty, exerciseID)
        let context = AvatarSceneNormalizationContext(frames: frames)
        let rig = NeutralMannequinRig()
        let sampled = stride(from: 0, to: frames.count, by: max(frames.count / 8, 1)).map { frames[$0] }

        for (index, frame) in sampled.enumerated() {
            let points = AvatarScenePointNormalizer.normalizedScenePoints(
                frame.landmarks,
                mirrored: false,
                context: context
            )
            rig.update(points: points)

            let head = try XCTUnwrap(Self.node("rig.head", in: rig.root), exerciseID)
            let neck = try XCTUnwrap(Self.node("rig.neck", in: rig.root), exerciseID)
            XCTAssertFalse(head.isHidden, "\(exerciseID)[\(index)] head hidden")
            XCTAssertFalse(neck.isHidden, "\(exerciseID)[\(index)] neck hidden")

            let shoulderCenter = Self.midpoint(
                points["primary.shoulder"] ?? points["left.shoulder"],
                points["secondary.shoulder"] ?? points["right.shoulder"]
            )
            let shoulder = try XCTUnwrap(shoulderCenter, "\(exerciseID)[\(index)] missing shoulders")

            // Head stays anatomically near the shoulder girdle (the June
            // failure showed it drifting far from the body).
            let headDistance = Self.distance(head.position, shoulder)
            XCTAssertLessThan(headDistance, 0.60, "\(exerciseID)[\(index)] head detached: \(headDistance)")
            XCTAssertGreaterThan(headDistance, 0.05, "\(exerciseID)[\(index)] head collapsed into shoulders")

            // The neck capsule bridges the shoulder girdle and the head.
            let neckToShoulder = Self.distance(neck.position, shoulder)
            let neckToHead = Self.distance(neck.position, head.position)
            XCTAssertLessThan(neckToShoulder, 0.45, "\(exerciseID)[\(index)] neck detached from torso: \(neckToShoulder)")
            XCTAssertLessThan(neckToHead, 0.45, "\(exerciseID)[\(index)] neck detached from head: \(neckToHead)")

            // The spine capsule bridges the shoulder girdle and the pelvis so
            // horizontal poses read as one connected body (the June review
            // failure showed the ribcage and hips as two separate pieces).
            let spine = try XCTUnwrap(Self.node("rig.spine", in: rig.root), exerciseID)
            let hipCenter = Self.midpoint(
                points["primary.hip"] ?? points["left.hip"],
                points["secondary.hip"] ?? points["right.hip"]
            )
            let hips = try XCTUnwrap(hipCenter, "\(exerciseID)[\(index)] missing hips")
            XCTAssertFalse(spine.isHidden, "\(exerciseID)[\(index)] spine hidden — torso reads as two pieces")
            let spineDrift = Self.distance(spine.position, Self.midpoint(shoulder, hips)!)
            XCTAssertLessThan(spineDrift, 0.20, "\(exerciseID)[\(index)] spine not bridging torso: \(spineDrift)")

            // Forearms anchor at the elbow midpoint when elbow+wrist exist.
            if let elbow = points["primary.elbow"], let wrist = points["primary.wrist"] {
                let forearm = try XCTUnwrap(Self.node("rig.near.forearm", in: rig.root), exerciseID)
                XCTAssertFalse(forearm.isHidden, "\(exerciseID)[\(index)] near forearm hidden")
                let expected = Self.midpoint(elbow, wrist)!
                let drift = Self.distance(forearm.position, expected)
                XCTAssertLessThan(drift, 0.12, "\(exerciseID)[\(index)] forearm detached: \(drift)")
            }
        }
    }

    /// Horizontal poses must not inherit standing-pose stance centering: when
    /// anchoring on the feet would push the body outside the visible frame,
    /// the context recenters on the body bounding box and scales to fit.
    func testHorizontalPoseContextRecentersAndFitsWidth() throws {
        let plankFrames = try Self.bundledFrames("bodyweight_plank")
        let context = try XCTUnwrap(AvatarSceneNormalizationContext(frames: plankFrames))

        let sampled = stride(from: 0, to: plankFrames.count, by: max(plankFrames.count / 6, 1))
        for index in sampled {
            let points = AvatarScenePointNormalizer.normalizedScenePoints(
                plankFrames[index].landmarks,
                mirrored: false,
                context: context
            )
            for name in ["nose", "primary.shoulder", "primary.hip", "primary.ankle", "primary.wrist"] {
                let point = try XCTUnwrap(points[name], name)
                XCTAssertLessThanOrEqual(abs(point.x), 1.0, "plank[\(index)] \(name) x out of frame: \(point.x)")
                XCTAssertGreaterThanOrEqual(point.y, -1.12, "plank[\(index)] \(name) below floor: \(point.y)")
                XCTAssertLessThanOrEqual(point.y, 1.24, "plank[\(index)] \(name) above ceiling: \(point.y)")
            }
        }
    }

    func testAllBundledTracesStayInFrame() throws {
        for exerciseID in [
            "bodyweight_squat", "bodyweight_lunge", "bodyweight_pushup",
            "single_arm_cable_tricep_extension", "standing_miniband_hip_flexion",
            "bodyweight_plank", "bodyweight_pike"
        ] {
            let frames = try Self.bundledFrames(exerciseID)
            let context = AvatarSceneNormalizationContext(frames: frames)
            for (index, frame) in frames.enumerated() where index % max(frames.count / 6, 1) == 0 {
                let points = AvatarScenePointNormalizer.normalizedScenePoints(
                    frame.landmarks,
                    mirrored: false,
                    context: context
                )
                for name in ["nose", "primary.shoulder", "primary.hip", "primary.ankle"] {
                    guard let point = points[name] else { continue }
                    XCTAssertLessThanOrEqual(
                        abs(point.x), 1.0,
                        "\(exerciseID)[\(index)] \(name) x out of frame: \(point.x)"
                    )
                }
            }
        }
    }

    // MARK: - Snapshot evidence

    /// Renders app-identical snapshots for human visual review. Writes PNGs
    /// under the directory named by CAMIFIT_RIG_SNAPSHOT_DIR when set.
    func testWriteReviewSnapshotsWhenRequested() throws {
        guard let outputDir = ProcessInfo.processInfo.environment["CAMIFIT_RIG_SNAPSHOT_DIR"] else {
            throw XCTSkip("CAMIFIT_RIG_SNAPSHOT_DIR not set; snapshot rendering is on-demand")
        }
        let directory = URL(fileURLWithPath: outputDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for exerciseID in ["bodyweight_plank", "bodyweight_pike", "standing_miniband_hip_flexion"] {
            let frames = try Self.bundledFrames(exerciseID)
            let context = AvatarSceneNormalizationContext(frames: frames)
            let scene = Self.appIdenticalScene()
            let rig = scene.rig
            let sampled = stride(from: 0, to: frames.count, by: max(frames.count / 6, 1)).map { frames[$0] }
            for (index, frame) in sampled.enumerated() {
                let points = AvatarScenePointNormalizer.normalizedScenePoints(
                    frame.landmarks,
                    mirrored: false,
                    context: context
                )
                rig.update(points: points)
                let image = Self.snapshot(scene: scene.scene)
                let url = directory.appendingPathComponent("\(exerciseID)_frame\(index).png")
                try Self.write(image, to: url)
            }
            print("rig-snapshots exercise=\(exerciseID) dir=\(directory.path)")
        }
    }

    // MARK: - Helpers

    private static func bundledFrames(_ exerciseID: String) throws -> [PoseFrame] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: exerciseID,
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ), exerciseID)
        return try MediaPipePoseProvider(jsonlURL: url).frames()
    }

    private static func node(_ name: String, in root: SCNNode) -> SCNNode? {
        root.childNode(withName: name, recursively: true)
    }

    private static func midpoint(_ a: SCNVector3?, _ b: SCNVector3?) -> SCNVector3? {
        guard let a else { return b }
        guard let b else { return a }
        return SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
    }

    private static func distance(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return CGFloat((dx * dx + dy * dy + dz * dz)).squareRoot()
    }

    private static func appIdenticalScene() -> (scene: SCNScene, rig: NeutralMannequinRig) {
        let scene = SCNScene()
        // The app stage draws over a dark backdrop; match it so pale torso
        // materials stay legible in review snapshots.
        scene.background.contents = NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.13, alpha: 1)
        let rig = NeutralMannequinRig()
        scene.rootNode.addChildNode(rig.root)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.78
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.05, 6.0)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight()
        key.type = .omni
        key.intensity = 850
        key.color = NSColor.cyan
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-2.2, 2.4, 3.8)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 300
        fill.color = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.58, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        return (scene, rig)
    }

    private static func snapshot(scene: SCNScene) -> NSImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        return renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 540, height: 960),
            antialiasingMode: .multisampling4X
        )
    }

    private static func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AvatarRigHorizontalPoseTests", code: 1)
        }
        try data.write(to: url)
    }
}
