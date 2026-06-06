import AppKit
import CamiFitEngine
import SceneKit
import simd
import SwiftUI

struct AvatarDemoStage: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel

    var body: some View {
        ZStack {
            AvatarDemoBackdrop()

            if let program = model.activeExerciseProgram {
                AvatarDemoTimelineView(program: program)
                    .padding(.vertical, 24)

                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Guide")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                            Text(program.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(18)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.system(size: 34, weight: .regular))
                    Text("No exercise selected")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

private struct AvatarDemoBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.026),
                    Color(red: 0.025, green: 0.075, blue: 0.070),
                    Color(red: 0.030, green: 0.035, blue: 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.18), .clear],
                center: .center,
                startRadius: 48,
                endRadius: 520
            )
            .blendMode(.screen)

            VStack {
                Spacer()
                Ellipse()
                    .fill(Color.yellow.opacity(0.10))
                    .frame(width: 300, height: 42)
                    .blur(radius: 10)
                    .padding(.bottom, 42)
            }
        }
    }
}

private struct AvatarDemoTimelineView: View {
    let program: ExerciseProgram
    private let timeline: MotionDemoTimeline

    init(program: ExerciseProgram) {
        self.program = program
        timeline = MotionDemoBundleStore.timeline(for: program) ?? MotionDemoCompiler.compile(program: program)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsedMS = elapsedMilliseconds(from: context.date)
            AvatarSceneView(frame: timeline.frame(atElapsedMS: elapsedMS))
                .allowsHitTesting(false)
        }
    }

    private func elapsedMilliseconds(from date: Date) -> Int64 {
        let raw = date.timeIntervalSinceReferenceDate * 1000
        return Int64(raw.truncatingRemainder(dividingBy: Double(timeline.durationMS)))
    }
}

private struct AvatarSceneView: NSViewRepresentable {
    let frame: PoseFrame

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(frame: frame)
    }

    final class Coordinator {
        let scene = SCNScene()
        private let avatarRoot = SCNNode()
        private let rig = NeutralMannequinRig()

        init() {
            scene.rootNode.addChildNode(avatarRoot)
            avatarRoot.addChildNode(rig.root)
            configureCamera()
            configureLights()
        }

        func update(frame: PoseFrame) {
            let points = normalizedScenePoints(frame.landmarks)
            rig.update(points: points)
        }

        private func configureCamera() {
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 1.78
            let node = SCNNode()
            node.camera = camera
            node.position = SCNVector3(0, 0.05, 6.0)
            scene.rootNode.addChildNode(node)
        }

        private func configureLights() {
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
        }

        private func normalizedScenePoints(_ landmarks: [String: PoseLandmark]) -> [String: SCNVector3] {
            var points = landmarks.mapValues(scenePoint)
            let visible = points.filter { AvatarRig.visibleJointNames.contains($0.key) }
            guard !visible.isEmpty else { return points }

            let minY = visible.map(\.value.y).min() ?? 0
            let minX = visible.map(\.value.x).min() ?? 0
            let maxX = visible.map(\.value.x).max() ?? 0
            let xCenter = (minX + maxX) / 2
            let yOffset = Self.floorY - minY

            for (key, point) in points {
                points[key] = SCNVector3(point.x - xCenter, point.y + yOffset, point.z)
            }

            return points
        }

        private func scenePoint(_ landmark: PoseLandmark) -> SCNVector3 {
            SCNVector3(
                Float((landmark.x - 0.52) * 3.45),
                Float((0.58 - landmark.y) * 3.10),
                Float(landmark.z * 1.80)
            )
        }

        private static let floorY: CGFloat = -1.06
    }
}

private final class NeutralMannequinRig {
    let root = SCNNode()

    private let head = SCNNode(geometry: SCNSphere(radius: 1))
    private let neck = SCNNode()
    private let chest = SCNNode(geometry: SCNSphere(radius: 1))
    private let torso = SCNNode()
    private let abdomen = SCNNode(geometry: SCNSphere(radius: 1))
    private let pelvis = SCNNode(geometry: SCNSphere(radius: 1))
    private let shoulderBridge = SCNNode()
    private let hipBridge = SCNNode()
    private let nearUpperArm = SCNNode()
    private let nearForearm = SCNNode()
    private let farUpperArm = SCNNode()
    private let farForearm = SCNNode()
    private let nearUpperLeg = SCNNode()
    private let nearLowerLeg = SCNNode()
    private let farUpperLeg = SCNNode()
    private let farLowerLeg = SCNNode()
    private let nearFoot = SCNNode()
    private let farFoot = SCNNode()
    private let nearHand = SCNNode(geometry: SCNSphere(radius: 1))
    private let farHand = SCNNode(geometry: SCNSphere(radius: 1))
    private let nearElbow = SCNNode(geometry: SCNSphere(radius: 1))
    private let farElbow = SCNNode(geometry: SCNSphere(radius: 1))
    private let nearKnee = SCNNode(geometry: SCNSphere(radius: 1))
    private let farKnee = SCNNode(geometry: SCNSphere(radius: 1))
    private let nearAnkle = SCNNode(geometry: SCNSphere(radius: 1))
    private let farAnkle = SCNNode(geometry: SCNSphere(radius: 1))

    private let torsoMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.86, green: 0.93, blue: 0.92, alpha: 1),
        emission: 0.035
    )
    private let limbMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.96, alpha: 1),
        emission: 0.03
    )
    private let farLimbMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.68, green: 0.78, blue: 0.77, alpha: 0.54),
        emission: 0.015
    )
    private let accentMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.78, green: 0.96, blue: 0.93, alpha: 1),
        emission: 0.045
    )

    init() {
        root.name = "camifit.avatar.mannequinRig"
        for node in allNodes {
            node.castsShadow = false
            root.addChildNode(node)
        }
        head.name = "rig.head"
        neck.name = "rig.neck"
        chest.name = "rig.chest"
        torso.name = "rig.spine"
        abdomen.name = "rig.abdomen"
        pelvis.name = "rig.pelvis"
        shoulderBridge.name = "rig.shoulderBridge"
        hipBridge.name = "rig.hipBridge"
        nearUpperArm.name = "rig.near.upperArm"
        nearForearm.name = "rig.near.forearm"
        farUpperArm.name = "rig.far.upperArm"
        farForearm.name = "rig.far.forearm"
        nearUpperLeg.name = "rig.near.upperLeg"
        nearLowerLeg.name = "rig.near.lowerLeg"
        farUpperLeg.name = "rig.far.upperLeg"
        farLowerLeg.name = "rig.far.lowerLeg"
        nearFoot.name = "rig.near.foot"
        farFoot.name = "rig.far.foot"
        nearHand.name = "rig.near.hand"
        farHand.name = "rig.far.hand"
        nearElbow.name = "rig.near.elbow"
        farElbow.name = "rig.far.elbow"
        nearKnee.name = "rig.near.knee"
        farKnee.name = "rig.far.knee"
        nearAnkle.name = "rig.near.ankle"
        farAnkle.name = "rig.far.ankle"

        head.geometry?.firstMaterial = accentMaterial
        head.simdScale = SIMD3<Float>(0.16, 0.20, 0.15)
        chest.geometry?.firstMaterial = torsoMaterial
        chest.simdScale = SIMD3<Float>(0.17, 0.22, 0.12)
        abdomen.geometry?.firstMaterial = torsoMaterial
        abdomen.simdScale = SIMD3<Float>(0.14, 0.18, 0.11)
        pelvis.geometry?.firstMaterial = torsoMaterial
        pelvis.simdScale = SIMD3<Float>(0.18, 0.13, 0.12)
        nearHand.geometry?.firstMaterial = limbMaterial
        nearHand.simdScale = SIMD3<Float>(0.055, 0.055, 0.045)
        farHand.geometry?.firstMaterial = farLimbMaterial
        farHand.simdScale = SIMD3<Float>(0.048, 0.048, 0.038)
        configureJointCaps()
    }

    func update(points: [String: SCNVector3]) {
        guard let primary = AvatarRig.side(named: "primary", in: points) else {
            root.isHidden = true
            return
        }
        root.isHidden = false

        let secondary = AvatarRig.side(named: "secondary", in: points)
            ?? AvatarRig.oppositePrimarySide(primary: primary, in: points)
        let headPoint = points["nose"] ?? SCNVector3(primary.shoulder.x, primary.shoulder.y + 0.34, primary.shoulder.z)

        let chestPoint = midpoint(primary.shoulder, primary.hip, factor: 0.28)
        let abdomenPoint = midpoint(primary.shoulder, primary.hip, factor: 0.66)

        updateCapsule(neck, from: primary.shoulder, to: headPoint, radius: 0.045, material: torsoMaterial)
        updateCapsule(torso, from: primary.shoulder, to: primary.hip, radius: 0.118, material: torsoMaterial)
        updateSphere(head, at: SCNVector3(headPoint.x, headPoint.y + 0.065, headPoint.z + 0.02))
        updateSphere(chest, at: chestPoint)
        updateSphere(abdomen, at: abdomenPoint)
        updateSphere(pelvis, at: primary.hip)

        if let elbow = primary.elbow, let wrist = primary.wrist {
            updateCapsule(nearUpperArm, from: primary.shoulder, to: elbow, radius: 0.050, material: limbMaterial)
            updateCapsule(nearForearm, from: elbow, to: wrist, radius: 0.043, material: limbMaterial)
            updateJoint(nearElbow, at: elbow, radius: 0.050)
            updateSphere(nearHand, at: wrist)
        } else {
            hide(nearUpperArm, nearForearm, nearHand, nearElbow)
        }

        updateCapsule(nearUpperLeg, from: primary.hip, to: primary.knee, radius: 0.078, material: limbMaterial)
        updateCapsule(nearLowerLeg, from: primary.knee, to: primary.ankle, radius: 0.064, material: limbMaterial)
        updateJoint(nearKnee, at: primary.knee, radius: 0.064)
        updateJoint(nearAnkle, at: primary.ankle, radius: 0.048)
        if let heel = primary.heel, let toe = primary.footIndex {
            updateFoot(nearFoot, from: heel, to: toe, maxLength: 0.28, thickness: 0.075, depth: 0.14, material: accentMaterial)
        } else {
            nearFoot.isHidden = true
        }

        if let secondary {
            updateCapsule(shoulderBridge, from: secondary.shoulder, to: primary.shoulder, radius: 0.052, material: torsoMaterial)
            updateCapsule(hipBridge, from: secondary.hip, to: primary.hip, radius: 0.060, material: torsoMaterial)
            if let elbow = secondary.elbow, let wrist = secondary.wrist {
                updateCapsule(farUpperArm, from: secondary.shoulder, to: elbow, radius: 0.040, material: farLimbMaterial)
                updateCapsule(farForearm, from: elbow, to: wrist, radius: 0.036, material: farLimbMaterial)
                updateJoint(farElbow, at: elbow, radius: 0.042)
                updateSphere(farHand, at: wrist)
            } else {
                hide(farUpperArm, farForearm, farHand, farElbow)
            }

            updateCapsule(farUpperLeg, from: secondary.hip, to: secondary.knee, radius: 0.054, material: farLimbMaterial)
            updateCapsule(farLowerLeg, from: secondary.knee, to: secondary.ankle, radius: 0.046, material: farLimbMaterial)
            updateJoint(farKnee, at: secondary.knee, radius: 0.050)
            updateJoint(farAnkle, at: secondary.ankle, radius: 0.040)
            if let heel = secondary.heel, let toe = secondary.footIndex {
                updateFoot(farFoot, from: heel, to: toe, maxLength: 0.24, thickness: 0.060, depth: 0.11, material: farLimbMaterial)
            } else {
                farFoot.isHidden = true
            }
        } else {
            hide(
                shoulderBridge, hipBridge,
                farUpperArm, farForearm, farHand, farElbow,
                farUpperLeg, farLowerLeg, farFoot, farKnee, farAnkle
            )
        }
    }

    private var allNodes: [SCNNode] {
        [
            farUpperArm, farForearm, farUpperLeg, farLowerLeg, farFoot, farHand,
            farElbow, farKnee, farAnkle,
            shoulderBridge, hipBridge,
            torso, chest, abdomen, pelvis, neck, head,
            nearUpperArm, nearForearm, nearUpperLeg, nearLowerLeg, nearFoot, nearHand,
            nearElbow, nearKnee, nearAnkle
        ]
    }

    private func configureJointCaps() {
        let nearJoints = [nearElbow, nearKnee, nearAnkle]
        let farJoints = [farElbow, farKnee, farAnkle]
        for node in nearJoints {
            node.geometry?.firstMaterial = limbMaterial
            node.simdScale = SIMD3<Float>(0.05, 0.05, 0.05)
        }
        for node in farJoints {
            node.geometry?.firstMaterial = farLimbMaterial
            node.simdScale = SIMD3<Float>(0.04, 0.04, 0.04)
        }
    }

    private func updateCapsule(_ node: SCNNode, from start: SCNVector3, to end: SCNVector3, radius: CGFloat, material: SCNMaterial) {
        let vector = SIMD3<Float>(
            Float(end.x - start.x),
            Float(end.y - start.y),
            Float(end.z - start.z)
        )
        let length = simd_length(vector)
        guard length > 0.0001 else {
            node.isHidden = true
            return
        }

        let geometry = SCNCapsule(capRadius: radius, height: CGFloat(length))
        geometry.radialSegmentCount = 24
        geometry.heightSegmentCount = 8
        geometry.firstMaterial = material
        node.geometry = geometry
        node.simdPosition = SIMD3<Float>(
            Float((start.x + end.x) / 2),
            Float((start.y + end.y) / 2),
            Float((start.z + end.z) / 2)
        )
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
        node.isHidden = false
    }

    private func updateFoot(
        _ node: SCNNode,
        from heel: SCNVector3,
        to toe: SCNVector3,
        maxLength: CGFloat,
        thickness: CGFloat,
        depth: CGFloat,
        material: SCNMaterial
    ) {
        let rawVector = SIMD3<Float>(
            Float(toe.x - heel.x),
            Float(toe.y - heel.y),
            Float(toe.z - heel.z)
        )
        let rawLength = simd_length(rawVector)
        guard rawLength > 0.0001 else {
            node.isHidden = true
            return
        }

        let direction = simd_normalize(rawVector)
        let length = min(CGFloat(rawLength), maxLength)
        let center = SIMD3<Float>(
            Float((heel.x + toe.x) / 2),
            Float((heel.y + toe.y) / 2),
            Float((heel.z + toe.z) / 2)
        )

        let geometry = SCNBox(
            width: length,
            height: thickness,
            length: depth,
            chamferRadius: min(thickness * 0.42, 0.03)
        )
        geometry.widthSegmentCount = 4
        geometry.heightSegmentCount = 2
        geometry.lengthSegmentCount = 4
        geometry.firstMaterial = material
        node.geometry = geometry
        node.simdPosition = center
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: direction)
        node.isHidden = false
    }

    private func updateSphere(_ node: SCNNode, at position: SCNVector3) {
        node.position = position
        node.isHidden = false
    }

    private func updateJoint(_ node: SCNNode, at position: SCNVector3, radius: Float) {
        node.position = position
        node.simdScale = SIMD3<Float>(radius, radius, radius)
        node.isHidden = false
    }

    private func midpoint(_ a: SCNVector3, _ b: SCNVector3, factor: CGFloat) -> SCNVector3 {
        let x = a.x + ((b.x - a.x) * factor)
        let y = a.y + ((b.y - a.y) * factor)
        let z = a.z + ((b.z - a.z) * factor)
        return SCNVector3(x, y, z)
    }

    private func hide(_ nodes: SCNNode...) {
        nodes.forEach { $0.isHidden = true }
    }

    private static func material(color: NSColor, emission: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(emission)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.82
        material.metalness.contents = 0.02
        material.transparency = color.alphaComponent
        return material
    }
}

private enum AvatarRig {
    struct Side {
        let shoulder: SCNVector3
        let hip: SCNVector3
        let knee: SCNVector3
        let ankle: SCNVector3
        let elbow: SCNVector3?
        let wrist: SCNVector3?
        let heel: SCNVector3?
        let footIndex: SCNVector3?
    }

    static let visibleJointNames: Set<String> = [
        "nose",
        "primary.shoulder", "primary.elbow", "primary.wrist", "primary.hip",
        "primary.knee", "primary.ankle", "primary.heel", "primary.foot.index",
        "secondary.shoulder", "secondary.elbow", "secondary.wrist", "secondary.hip",
        "secondary.knee", "secondary.ankle", "secondary.heel", "secondary.foot.index",
        "left.shoulder", "left.elbow", "left.wrist", "left.hip", "left.knee", "left.ankle", "left.heel", "left.foot.index",
        "right.shoulder", "right.elbow", "right.wrist", "right.hip", "right.knee", "right.ankle", "right.heel", "right.foot.index"
    ]

    static func side(named prefix: String, in points: [String: SCNVector3]) -> Side? {
        guard let shoulder = points["\(prefix).shoulder"],
              let hip = points["\(prefix).hip"],
              let knee = points["\(prefix).knee"],
              let ankle = points["\(prefix).ankle"] else {
            return nil
        }

        return Side(
            shoulder: shoulder,
            hip: hip,
            knee: knee,
            ankle: ankle,
            elbow: points["\(prefix).elbow"],
            wrist: points["\(prefix).wrist"],
            heel: points["\(prefix).heel"],
            footIndex: points["\(prefix).foot.index"]
        )
    }

    static func oppositePrimarySide(primary: Side, in points: [String: SCNVector3]) -> Side? {
        let candidates = ["left", "right"].compactMap { side(named: $0, in: points) }
        return candidates.max { lhs, rhs in
            distanceSquared(lhs.hip, primary.hip) < distanceSquared(rhs.hip, primary.hip)
        }
    }

    private static func distanceSquared(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return (dx * dx) + (dy * dy) + (dz * dz)
    }
}

private enum MotionDemoBundleStore {
    static func timeline(for program: ExerciseProgram) -> MotionDemoTimeline? {
        guard let url = Bundle.module.url(
            forResource: program.id,
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ) else {
            return nil
        }

        do {
            let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: url)
            guard !frames.isEmpty else { return nil }
            let duration = (frames.last?.timestampMS ?? 0) + 100
            return MotionDemoTimeline(
                programID: program.id,
                programName: program.name,
                source: .trainerReferenceTrace(provenance: "Bundled reference trace: \(url.lastPathComponent)"),
                frames: frames,
                durationMS: duration
            )
        } catch {
            return nil
        }
    }
}
