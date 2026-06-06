import GLTFKit2
import SceneKit
import XCTest
@testable import CamiFitApp

final class AvatarHumanoidGLBAssetTests: XCTestCase {
    func testNeutralHumanoidGLBLoadsWithRequiredRigNodes() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "neutral_humanoid",
            withExtension: "glb",
            subdirectory: "Avatars"
        ))
        let asset = try GLTFAsset(url: url)
        let source = GLTFSCNSceneSource(asset: asset)
        let root = try XCTUnwrap(source.defaultScene?.rootNode)

        for name in Self.requiredNodeNames {
            XCTAssertNotNil(Self.node(name, in: root), "Missing GLB rig node \(name)")
        }
    }

    private static func node(_ name: String, in root: SCNNode) -> SCNNode? {
        root.childNode(withName: name, recursively: true)
            ?? root.childNode(withName: name.replacingOccurrences(of: ".", with: "_"), recursively: true)
    }

    private static let requiredNodeNames = [
        "avatar.head",
        "avatar.neck",
        "avatar.chest",
        "avatar.spine",
        "avatar.abdomen",
        "avatar.pelvis",
        "avatar.shoulderBridge",
        "avatar.hipBridge",
        "avatar.near.upperArm",
        "avatar.near.forearm",
        "avatar.far.upperArm",
        "avatar.far.forearm",
        "avatar.near.upperLeg",
        "avatar.near.lowerLeg",
        "avatar.far.upperLeg",
        "avatar.far.lowerLeg",
        "avatar.near.foot",
        "avatar.far.foot",
        "avatar.near.hand",
        "avatar.far.hand",
        "avatar.near.elbow",
        "avatar.far.elbow",
        "avatar.near.knee",
        "avatar.far.knee",
        "avatar.near.ankle",
        "avatar.far.ankle",
    ]
}
