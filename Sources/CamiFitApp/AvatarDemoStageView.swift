import AppKit
import CamiFitEngine
import GLTFKit2
import os
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
    private let timeline: MotionDemoTimeline?
    private let normalizationContext: AvatarSceneNormalizationContext?

    init(program: ExerciseProgram) {
        self.program = program
        let resolvedTimeline = MotionDemoBundleStore.guideTimeline(for: program)
        timeline = resolvedTimeline
        normalizationContext = resolvedTimeline.flatMap { AvatarSceneNormalizationContext(frames: $0.frames) }
    }

    var body: some View {
        if let timeline {
            if let fixedElapsedMS = Self.fixedGuideElapsedMS {
                AvatarSceneView(
                    frame: timeline.frame(atElapsedMS: fixedElapsedMS),
                    normalizationContext: normalizationContext
                )
                    .allowsHitTesting(false)
            } else {
                TimelineView(.animation) { context in
                    let elapsedMS = elapsedMilliseconds(from: context.date, timeline: timeline)
                    AvatarSceneView(
                        frame: timeline.frame(atElapsedMS: elapsedMS),
                        normalizationContext: normalizationContext
                    )
                        .allowsHitTesting(false)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 34, weight: .regular))
                Text("Reference clip needed")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
    }

    private func elapsedMilliseconds(from date: Date, timeline: MotionDemoTimeline) -> Int64 {
        let raw = date.timeIntervalSinceReferenceDate * 1000
        return Int64(raw.truncatingRemainder(dividingBy: Double(timeline.durationMS)))
    }

    private static var fixedGuideElapsedMS: Int64? {
        guard let raw = ProcessInfo.processInfo.environment["CAMIFIT_GUIDE_FRAME_MS"],
              let elapsedMS = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return elapsedMS
    }
}

private struct AvatarSceneView: NSViewRepresentable {
    let frame: PoseFrame
    var mirrored = false
    var normalizationContext: AvatarSceneNormalizationContext?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        view.isPlaying = false
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(
            frame: frame,
            mirrored: mirrored,
            normalizationContext: normalizationContext
        )
        nsView.needsDisplay = true
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

        func update(frame: PoseFrame, mirrored: Bool, normalizationContext: AvatarSceneNormalizationContext?) {
            let points = AvatarScenePointNormalizer.normalizedScenePoints(
                frame.landmarks,
                mirrored: mirrored,
                context: normalizationContext
            )
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

    }
}

struct AvatarSceneNormalizationContext: Equatable {
    let xCenter: CGFloat
    let yOffset: CGFloat
    let scale: CGFloat

    init?(frames: [PoseFrame], mirrored: Bool = false) {
        let framePoints = frames
            .map { AvatarScenePointNormalizer.rawScenePoints($0.landmarks, mirrored: mirrored) }
            .filter { !$0.isEmpty }
        guard !framePoints.isEmpty else { return nil }

        self = Self.context(for: framePoints)
    }

    fileprivate static func context(for framePoints: [[String: SCNVector3]]) -> AvatarSceneNormalizationContext {
        let visiblePoints = framePoints.flatMap { points in
            points.filter { AvatarRig.visibleJointNames.contains($0.key) }.map(\.value)
        }
        let fallbackPoints = framePoints.flatMap { Array($0.values) }
        let points = visiblePoints.isEmpty ? fallbackPoints : visiblePoints
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? minY

        let stanceCenters = framePoints.compactMap { AvatarScenePointNormalizer.stanceCenterX(in: $0) }
        let xCenter: CGFloat
        if stanceCenters.isEmpty {
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            xCenter = (minX + maxX) / 2
        } else {
            xCenter = stanceCenters.reduce(CGFloat(0), +) / CGFloat(stanceCenters.count)
        }

        let yOffset = AvatarScenePointNormalizer.floorY - minY
        let maxYAfterOffset = maxY + yOffset
        let scale = maxYAfterOffset > AvatarScenePointNormalizer.ceilingY
            ? (AvatarScenePointNormalizer.ceilingY - AvatarScenePointNormalizer.floorY)
                / max(maxYAfterOffset - AvatarScenePointNormalizer.floorY, 0.000_001)
            : 1

        return AvatarSceneNormalizationContext(xCenter: xCenter, yOffset: yOffset, scale: scale)
    }

    private init(xCenter: CGFloat, yOffset: CGFloat, scale: CGFloat) {
        self.xCenter = xCenter
        self.yOffset = yOffset
        self.scale = scale
    }
}

enum AvatarScenePointNormalizer {
    static func normalizedScenePoints(
        _ landmarks: [String: PoseLandmark],
        mirrored: Bool,
        context: AvatarSceneNormalizationContext? = nil
    ) -> [String: SCNVector3] {
        let points = rawScenePoints(landmarks, mirrored: mirrored)
        guard !points.isEmpty else { return points }
        let context = context ?? AvatarSceneNormalizationContext.context(for: [points])

        return normalized(points, context: context)
    }

    fileprivate static func rawScenePoints(_ landmarks: [String: PoseLandmark], mirrored: Bool) -> [String: SCNVector3] {
        landmarks.mapValues { scenePoint($0, mirrored: mirrored) }
    }

    private static func normalized(
        _ rawPoints: [String: SCNVector3],
        context: AvatarSceneNormalizationContext
    ) -> [String: SCNVector3] {
        var points = rawPoints
        guard !points.isEmpty else { return points }

        for (key, point) in points {
            points[key] = SCNVector3(point.x - context.xCenter, point.y + context.yOffset, point.z)
        }

        if context.scale < 1 {
            for (key, point) in points {
                points[key] = SCNVector3(
                    point.x * context.scale,
                    floorY + ((point.y - floorY) * context.scale),
                    point.z * context.scale
                )
            }
        }

        return points
    }

    private static func scenePoint(_ landmark: PoseLandmark, mirrored: Bool) -> SCNVector3 {
        let x = Float((landmark.x - 0.52) * 3.45)
        return SCNVector3(
            mirrored ? -x : x,
            Float((0.58 - landmark.y) * 3.10),
            Float(landmark.z * 1.80)
        )
    }

    fileprivate static func stanceCenterX(in points: [String: SCNVector3]) -> CGFloat? {
        let primaryCenters = footCenters(for: ["primary", "secondary"], in: points)
        if primaryCenters.count >= 2 {
            return averageX(primaryCenters)
        }

        let sideCenters = footCenters(for: ["left", "right"], in: points)
        if sideCenters.count >= 2 {
            return averageX(sideCenters)
        }

        if !primaryCenters.isEmpty {
            return averageX(primaryCenters)
        }

        if !sideCenters.isEmpty {
            return averageX(sideCenters)
        }

        return nil
    }

    private static func footCenters(for prefixes: [String], in points: [String: SCNVector3]) -> [SCNVector3] {
        prefixes.compactMap { prefix in
            guard let heel = points["\(prefix).heel"],
                  let toe = points["\(prefix).foot.index"] else {
                return nil
            }
            return SCNVector3(
                (heel.x + toe.x) / 2,
                (heel.y + toe.y) / 2,
                (heel.z + toe.z) / 2
            )
        }
    }

    private static func averageX(_ points: [SCNVector3]) -> CGFloat {
        points.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(points.count)
    }

    fileprivate static let floorY: CGFloat = -1.06
    fileprivate static let ceilingY: CGFloat = 1.18
}

enum AvatarHeadPlacement {
    static func shouldUseRawAttachment(torsoAxis: SCNVector3) -> Bool {
        isHorizontalPose(torsoAxis) || isInvertedPose(torsoAxis)
    }

    static func isHorizontalPose(_ torsoAxis: SCNVector3) -> Bool {
        abs(torsoAxis.x) > abs(torsoAxis.y) * 1.15
    }

    static func isInvertedPose(_ torsoAxis: SCNVector3) -> Bool {
        torsoAxis.y > 0
    }
}

struct AvatarReferencePoseView: View {
    let frame: PoseFrame
    let opacity: Double
    let matchProgress: Double
    let mirrored: Bool
    let normalizationContext: AvatarSceneNormalizationContext?

    init(
        frame: PoseFrame,
        opacity: Double = 0.42,
        matchProgress: Double = 0,
        mirrored: Bool = false,
        normalizationContext: AvatarSceneNormalizationContext? = nil
    ) {
        self.frame = frame
        self.opacity = opacity
        self.matchProgress = matchProgress
        self.mirrored = mirrored
        self.normalizationContext = normalizationContext
    }

    var body: some View {
        AvatarSceneView(frame: frame, mirrored: mirrored, normalizationContext: normalizationContext)
            .opacity(min(max(opacity + (matchProgress * 0.14), 0.24), 0.70))
            .saturation(0.82 + (matchProgress * 0.18))
            .shadow(color: .green.opacity(0.22 * matchProgress), radius: 18 * matchProgress, y: 4)
            .compositingGroup()
    }
}

private final class NeutralMannequinRig {
    let root: SCNNode

    private let head: SCNNode
    private let neck: SCNNode
    private let chest: SCNNode
    private let torso: SCNNode
    private let abdomen: SCNNode
    private let pelvis: SCNNode
    private let shoulderBridge: SCNNode
    private let hipBridge: SCNNode
    private let nearUpperArm: SCNNode
    private let nearForearm: SCNNode
    private let farUpperArm: SCNNode
    private let farForearm: SCNNode
    private let nearUpperLeg: SCNNode
    private let nearLowerLeg: SCNNode
    private let farUpperLeg: SCNNode
    private let farLowerLeg: SCNNode
    private let nearFootBridge = SCNNode()
    private let farFootBridge = SCNNode()
    private let nearFoot: SCNNode
    private let farFoot: SCNNode
    private let nearHand: SCNNode
    private let farHand: SCNNode
    private let nearElbow: SCNNode
    private let farElbow: SCNNode
    private let nearKnee: SCNNode
    private let farKnee: SCNNode
    private let nearAnkle: SCNNode
    private let farAnkle: SCNNode
    private let usesAssetGeometry: Bool

    private let torsoMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.86, green: 0.93, blue: 0.92, alpha: 1),
        emission: 0.035
    )
    private let limbMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.96, alpha: 1),
        emission: 0.03
    )
    private let farLimbMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.62, green: 0.74, blue: 0.73, alpha: 1),
        emission: 0.015
    )
    private let accentMaterial = NeutralMannequinRig.material(
        color: NSColor(calibratedRed: 0.78, green: 0.96, blue: 0.93, alpha: 1),
        emission: 0.045
    )

    init() {
        if let asset = AvatarHumanoidGLBAsset.loadNeutralRig() {
            root = asset.root
            head = asset.head
            neck = asset.neck
            chest = asset.chest
            torso = asset.torso
            abdomen = asset.abdomen
            pelvis = asset.pelvis
            shoulderBridge = asset.shoulderBridge
            hipBridge = asset.hipBridge
            nearUpperArm = asset.nearUpperArm
            nearForearm = asset.nearForearm
            farUpperArm = asset.farUpperArm
            farForearm = asset.farForearm
            nearUpperLeg = asset.nearUpperLeg
            nearLowerLeg = asset.nearLowerLeg
            farUpperLeg = asset.farUpperLeg
            farLowerLeg = asset.farLowerLeg
            nearFoot = asset.nearFoot
            farFoot = asset.farFoot
            nearHand = asset.nearHand
            farHand = asset.farHand
            nearElbow = asset.nearElbow
            farElbow = asset.farElbow
            nearKnee = asset.nearKnee
            farKnee = asset.farKnee
            nearAnkle = asset.nearAnkle
            farAnkle = asset.farAnkle
            usesAssetGeometry = true
        } else {
            AvatarDiagnostics.logger.warning("neutral_humanoid.glb unavailable; using in-code avatar fallback")
            root = SCNNode()
            head = SCNNode(geometry: SCNSphere(radius: 1))
            neck = SCNNode()
            chest = SCNNode(geometry: SCNSphere(radius: 1))
            torso = SCNNode()
            abdomen = SCNNode(geometry: SCNSphere(radius: 1))
            pelvis = SCNNode(geometry: SCNSphere(radius: 1))
            shoulderBridge = SCNNode()
            hipBridge = SCNNode()
            nearUpperArm = SCNNode()
            nearForearm = SCNNode()
            farUpperArm = SCNNode()
            farForearm = SCNNode()
            nearUpperLeg = SCNNode()
            nearLowerLeg = SCNNode()
            farUpperLeg = SCNNode()
            farLowerLeg = SCNNode()
            nearFoot = SCNNode()
            farFoot = SCNNode()
            nearHand = SCNNode(geometry: SCNSphere(radius: 1))
            farHand = SCNNode(geometry: SCNSphere(radius: 1))
            nearElbow = SCNNode(geometry: SCNSphere(radius: 1))
            farElbow = SCNNode(geometry: SCNSphere(radius: 1))
            nearKnee = SCNNode(geometry: SCNSphere(radius: 1))
            farKnee = SCNNode(geometry: SCNSphere(radius: 1))
            nearAnkle = SCNNode(geometry: SCNSphere(radius: 1))
            farAnkle = SCNNode(geometry: SCNSphere(radius: 1))
            usesAssetGeometry = false
            for node in allNodes {
                root.addChildNode(node)
            }
        }
        if nearFootBridge.parent == nil {
            root.addChildNode(nearFootBridge)
        }
        if farFootBridge.parent == nil {
            root.addChildNode(farFootBridge)
        }

        root.name = usesAssetGeometry ? "camifit.avatar.glbHumanoidRig" : "camifit.avatar.mannequinRig"
        for node in allNodes {
            node.castsShadow = false
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
        nearFootBridge.name = "rig.near.footBridge"
        farFootBridge.name = "rig.far.footBridge"
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
        head.simdScale = usesAssetGeometry ? SIMD3<Float>(0.15, 0.19, 0.14) : SIMD3<Float>(0.16, 0.20, 0.15)
        chest.geometry?.firstMaterial = torsoMaterial
        chest.simdScale = usesAssetGeometry ? SIMD3<Float>(0.18, 0.34, 0.12) : SIMD3<Float>(0.17, 0.22, 0.12)
        abdomen.geometry?.firstMaterial = torsoMaterial
        abdomen.simdScale = SIMD3<Float>(0.14, 0.18, 0.11)
        pelvis.geometry?.firstMaterial = torsoMaterial
        pelvis.simdScale = usesAssetGeometry ? SIMD3<Float>(0.18, 0.11, 0.12) : SIMD3<Float>(0.18, 0.13, 0.12)
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

        let shoulderCenter = secondary.map { midpoint($0.shoulder, primary.shoulder, factor: 0.5) } ?? primary.shoulder
        let hipCenter = secondary.map { midpoint($0.hip, primary.hip, factor: 0.5) } ?? primary.hip
        let visualPrimary = usesAssetGeometry
            ? retargetVisualLowerLeg(primary, maxRatio: Self.primaryLowerLegMaxRatio)
            : primary
        let visualSecondary = secondary.map {
            usesAssetGeometry
                ? retargetVisualLowerLeg($0, maxRatio: Self.secondaryLowerLegMaxRatio)
                : $0
        }

        let chestPoint = midpoint(
            shoulderCenter,
            hipCenter,
            factor: usesAssetGeometry ? Self.assetChestCenterFactor : 0.28
        )
        let torsoAxis = SCNVector3(
            hipCenter.x - shoulderCenter.x,
            hipCenter.y - shoulderCenter.y,
            hipCenter.z - shoulderCenter.z
        )
        let shouldUseRawHeadAttachment = AvatarHeadPlacement.shouldUseRawAttachment(torsoAxis: torsoAxis)
        let rawHeadCenter = SCNVector3(headPoint.x, headPoint.y + 0.005, headPoint.z + 0.02)
        let headCenter = usesAssetGeometry && !shouldUseRawHeadAttachment
            ? headAnchoredToTorso(rawHeadCenter, chestCenter: chestPoint)
            : rawHeadCenter
        let neckBottom: SCNVector3
        let neckTop: SCNVector3
        if usesAssetGeometry && shouldUseRawHeadAttachment {
            neckBottom = midpoint(shoulderCenter, headCenter, factor: 0.20)
            neckTop = midpoint(shoulderCenter, headCenter, factor: 0.58)
        } else {
            if usesAssetGeometry {
                neckBottom = midpoint(shoulderCenter, chestPoint, factor: 0.18)
                neckTop = midpoint(neckBottom, headCenter, factor: 0.72)
            } else {
                neckBottom = SCNVector3(shoulderCenter.x, shoulderCenter.y + 0.050, shoulderCenter.z)
                neckTop = SCNVector3(
                    neckBottom.x,
                    max(neckBottom.y + 0.035, headCenter.y - Self.assetNeckHeadAttachmentOffset),
                    neckBottom.z + 0.01
                )
            }
        }

        updateCapsule(neck, from: neckBottom, to: neckTop, radius: 0.034, material: torsoMaterial)
        updateSphere(head, at: headCenter)

        updateOrientedBodyMass(chest, at: chestPoint, along: torsoAxis)
        updateOrientedBodyMass(pelvis, at: hipCenter, along: torsoAxis)
        hide(torso, abdomen, shoulderBridge, hipBridge)

        if let elbow = primary.elbow, let wrist = primary.wrist {
            updateCapsule(nearUpperArm, from: primary.shoulder, to: elbow, radius: 0.050, material: limbMaterial)
            updateCapsule(nearForearm, from: elbow, to: wrist, radius: 0.043, material: limbMaterial)
            updateJoint(nearElbow, at: elbow, radius: 0.050)
            updateSphere(nearHand, at: wrist)
        } else {
            hide(nearUpperArm, nearForearm, nearHand, nearElbow)
        }

        updateCapsule(nearUpperLeg, from: visualPrimary.hip, to: visualPrimary.knee, radius: 0.078, material: limbMaterial)
        updateCapsule(nearLowerLeg, from: visualPrimary.knee, to: visualPrimary.ankle, radius: 0.064, material: limbMaterial)
        updateJoint(nearKnee, at: visualPrimary.knee, radius: 0.064)
        updateJoint(nearAnkle, at: visualPrimary.ankle, radius: 0.048)
        if let heel = primary.heel, let toe = primary.footIndex {
            updateCapsule(
                nearFootBridge,
                from: visualPrimary.ankle,
                to: footAttachmentPoint(ankle: visualPrimary.ankle, heel: heel, toe: toe),
                radius: 0.036,
                material: limbMaterial
            )
            updateFoot(nearFoot, from: heel, to: toe, maxLength: 0.28, thickness: 0.075, depth: 0.14, material: accentMaterial)
        } else {
            nearFootBridge.isHidden = true
            nearFoot.isHidden = true
        }

        if let secondary, let visualSecondary {
            hide(shoulderBridge, hipBridge)
            if let elbow = secondary.elbow, let wrist = secondary.wrist {
                updateCapsule(farUpperArm, from: secondary.shoulder, to: elbow, radius: 0.040, material: farLimbMaterial)
                updateCapsule(farForearm, from: elbow, to: wrist, radius: 0.036, material: farLimbMaterial)
                updateJoint(farElbow, at: elbow, radius: 0.042)
                updateSphere(farHand, at: wrist)
            } else {
                hide(farUpperArm, farForearm, farHand, farElbow)
            }

            updateCapsule(farUpperLeg, from: visualSecondary.hip, to: visualSecondary.knee, radius: 0.054, material: farLimbMaterial)
            updateCapsule(farLowerLeg, from: visualSecondary.knee, to: visualSecondary.ankle, radius: 0.046, material: farLimbMaterial)
            updateJoint(farKnee, at: visualSecondary.knee, radius: 0.050)
            updateJoint(farAnkle, at: visualSecondary.ankle, radius: 0.040)
            if let heel = secondary.heel, let toe = secondary.footIndex {
                updateCapsule(
                    farFootBridge,
                    from: visualSecondary.ankle,
                    to: footAttachmentPoint(ankle: visualSecondary.ankle, heel: heel, toe: toe),
                    radius: 0.030,
                    material: farLimbMaterial
                )
                updateFoot(farFoot, from: heel, to: toe, maxLength: 0.24, thickness: 0.060, depth: 0.11, material: farLimbMaterial)
            } else {
                farFootBridge.isHidden = true
                farFoot.isHidden = true
            }
        } else {
            hide(
                shoulderBridge, hipBridge,
                farUpperArm, farForearm, farHand, farElbow,
                farUpperLeg, farLowerLeg, farFootBridge, farFoot, farKnee, farAnkle
            )
        }
    }

    private var allNodes: [SCNNode] {
        [
            farUpperArm, farForearm, farUpperLeg, farLowerLeg, farFootBridge, farFoot, farHand,
            farElbow, farKnee, farAnkle,
            shoulderBridge, hipBridge,
            torso, chest, abdomen, pelvis, neck, head,
            nearUpperArm, nearForearm, nearUpperLeg, nearLowerLeg, nearFootBridge, nearFoot, nearHand,
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

        if usesAssetGeometry {
            if node.geometry == nil {
                let geometry = SCNCapsule(capRadius: CGFloat(Self.assetCapsuleRadius), height: CGFloat(Self.assetCapsuleHeight))
                geometry.radialSegmentCount = 18
                geometry.heightSegmentCount = 4
                geometry.firstMaterial = material
                node.geometry = geometry
            }
            node.simdPosition = SIMD3<Float>(
                Float((start.x + end.x) / 2),
                Float((start.y + end.y) / 2),
                Float((start.z + end.z) / 2)
            )
            node.simdScale = SIMD3<Float>(
                Float(radius) / Self.assetCapsuleRadius,
                length / Self.assetCapsuleHeight,
                Float(radius) / Self.assetCapsuleRadius
            )
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
            node.isHidden = false
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

        if usesAssetGeometry {
            node.simdPosition = center
            node.simdScale = SIMD3<Float>(Float(length), Float(thickness), Float(depth))
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: direction)
            node.isHidden = false
            return
        }

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

    private func footAttachmentPoint(ankle: SCNVector3, heel: SCNVector3, toe: SCNVector3) -> SCNVector3 {
        let foot = SIMD3<Float>(
            Float(toe.x - heel.x),
            Float(toe.y - heel.y),
            Float(toe.z - heel.z)
        )
        let footLengthSquared = simd_length_squared(foot)
        guard footLengthSquared > 0.0001 else { return heel }

        let ankleOffset = SIMD3<Float>(
            Float(ankle.x - heel.x),
            Float(ankle.y - heel.y),
            Float(ankle.z - heel.z)
        )
        let projection = max(0, min(1, simd_dot(ankleOffset, foot) / footLengthSquared))
        return SCNVector3(
            heel.x + ((toe.x - heel.x) * CGFloat(projection)),
            heel.y + ((toe.y - heel.y) * CGFloat(projection)),
            heel.z + ((toe.z - heel.z) * CGFloat(projection))
        )
    }

    private func updateSphere(_ node: SCNNode, at position: SCNVector3) {
        node.position = position
        node.isHidden = false
    }

    private func updateOrientedBodyMass(_ node: SCNNode, at position: SCNVector3, along axis: SCNVector3) {
        updateSphere(node, at: position)
        let vector = SIMD3<Float>(Float(axis.x), Float(axis.y), Float(axis.z))
        guard simd_length(vector) > 0.0001 else { return }
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
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

    private func headAnchoredToTorso(_ rawHeadCenter: SCNVector3, chestCenter: SCNVector3) -> SCNVector3 {
        SCNVector3(
            rawHeadCenter.x,
            chestCenter.y + Self.assetHeadHeightAboveChestCenter,
            rawHeadCenter.z
        )
    }

    private func retargetVisualLowerLeg(_ side: AvatarRig.Side, maxRatio: CGFloat) -> AvatarRig.Side {
        let lowerLegLength = distance(side.knee, side.ankle)
        let upperLegLength = distance(side.hip, side.knee)
        guard upperLegLength > 0.0001,
              lowerLegLength > 0.0001,
              lowerLegLength / upperLegLength > maxRatio else {
            return side
        }

        let direction = unitVector(from: side.ankle, to: side.knee)
        var low: CGFloat = 0
        var high = lowerLegLength
        for _ in 0..<18 {
            let candidateLength = (low + high) / 2
            let candidateKnee = point(from: side.ankle, along: direction, distance: candidateLength)
            let candidateUpperLegLength = distance(side.hip, candidateKnee)
            guard candidateUpperLegLength > 0.0001 else {
                high = candidateLength
                continue
            }

            if candidateLength / candidateUpperLegLength > maxRatio {
                high = candidateLength
            } else {
                low = candidateLength
            }
        }

        let adjustedKnee = point(from: side.ankle, along: direction, distance: low)
        return AvatarRig.Side(
            shoulder: side.shoulder,
            hip: side.hip,
            knee: adjustedKnee,
            ankle: side.ankle,
            elbow: side.elbow,
            wrist: side.wrist,
            heel: side.heel,
            footIndex: side.footIndex
        )
    }

    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt((dx * dx) + (dy * dy) + (dz * dz))
    }

    private func unitVector(from start: SCNVector3, to end: SCNVector3) -> SCNVector3 {
        let length = distance(start, end)
        guard length > 0.0001 else { return SCNVector3(0, 1, 0) }
        return SCNVector3(
            (end.x - start.x) / length,
            (end.y - start.y) / length,
            (end.z - start.z) / length
        )
    }

    private func point(from start: SCNVector3, along direction: SCNVector3, distance: CGFloat) -> SCNVector3 {
        SCNVector3(
            start.x + (direction.x * distance),
            start.y + (direction.y * distance),
            start.z + (direction.z * distance)
        )
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

    private static let assetCapsuleRadius: Float = 0.18
    private static let assetCapsuleHeight: Float = 1.0
    private static let primaryLowerLegMaxRatio: CGFloat = 1.22
    private static let secondaryLowerLegMaxRatio: CGFloat = 1.22
    private static let assetChestCenterFactor: CGFloat = 0.42
    private static let assetNeckChestAttachmentOffset: CGFloat = 0.30
    private static let assetNeckHeadAttachmentOffset: CGFloat = 0.155
    private static let assetHeadHeightAboveChestCenter: CGFloat = 0.60
}

private struct AvatarHumanoidGLBAsset {
    let root: SCNNode
    let head: SCNNode
    let neck: SCNNode
    let chest: SCNNode
    let torso: SCNNode
    let abdomen: SCNNode
    let pelvis: SCNNode
    let shoulderBridge: SCNNode
    let hipBridge: SCNNode
    let nearUpperArm: SCNNode
    let nearForearm: SCNNode
    let farUpperArm: SCNNode
    let farForearm: SCNNode
    let nearUpperLeg: SCNNode
    let nearLowerLeg: SCNNode
    let farUpperLeg: SCNNode
    let farLowerLeg: SCNNode
    let nearFoot: SCNNode
    let farFoot: SCNNode
    let nearHand: SCNNode
    let farHand: SCNNode
    let nearElbow: SCNNode
    let farElbow: SCNNode
    let nearKnee: SCNNode
    let farKnee: SCNNode
    let nearAnkle: SCNNode
    let farAnkle: SCNNode

    static func loadNeutralRig() -> AvatarHumanoidGLBAsset? {
        guard let url = AppResourceBundle.url(
            forResource: "neutral_humanoid",
            withExtension: "glb",
            subdirectory: "Avatars"
        ) else {
            AvatarDiagnostics.logger.error("neutral_humanoid.glb missing from packaged Avatars resources")
            return nil
        }

        do {
            let asset = try GLTFAsset(url: url)
            let source = GLTFSCNSceneSource(asset: asset)
            guard let sceneRoot = source.defaultScene?.rootNode else {
                AvatarDiagnostics.logger.error("neutral_humanoid.glb loaded but did not produce a default SceneKit scene")
                return nil
            }
            let importedRoot = node("avatar.root", in: sceneRoot) ?? sceneRoot
            let root = importedRoot.clone()

            guard let head = node("avatar.head", in: root),
                  let neck = node("avatar.neck", in: root),
                  let chest = node("avatar.chest", in: root),
                  let torso = node("avatar.spine", in: root),
                  let abdomen = node("avatar.abdomen", in: root),
                  let pelvis = node("avatar.pelvis", in: root),
                  let shoulderBridge = node("avatar.shoulderBridge", in: root),
                  let hipBridge = node("avatar.hipBridge", in: root),
                  let nearUpperArm = node("avatar.near.upperArm", in: root),
                  let nearForearm = node("avatar.near.forearm", in: root),
                  let farUpperArm = node("avatar.far.upperArm", in: root),
                  let farForearm = node("avatar.far.forearm", in: root),
                  let nearUpperLeg = node("avatar.near.upperLeg", in: root),
                  let nearLowerLeg = node("avatar.near.lowerLeg", in: root),
                  let farUpperLeg = node("avatar.far.upperLeg", in: root),
                  let farLowerLeg = node("avatar.far.lowerLeg", in: root),
                  let nearFoot = node("avatar.near.foot", in: root),
                  let farFoot = node("avatar.far.foot", in: root),
                  let nearHand = node("avatar.near.hand", in: root),
                  let farHand = node("avatar.far.hand", in: root),
                  let nearElbow = node("avatar.near.elbow", in: root),
                  let farElbow = node("avatar.far.elbow", in: root),
                  let nearKnee = node("avatar.near.knee", in: root),
                  let farKnee = node("avatar.far.knee", in: root),
                  let nearAnkle = node("avatar.near.ankle", in: root),
                  let farAnkle = node("avatar.far.ankle", in: root) else {
                AvatarDiagnostics.logger.error("neutral_humanoid.glb loaded but one or more required rig nodes were missing")
                return nil
            }

            return AvatarHumanoidGLBAsset(
                root: root,
                head: head,
                neck: neck,
                chest: chest,
                torso: torso,
                abdomen: abdomen,
                pelvis: pelvis,
                shoulderBridge: shoulderBridge,
                hipBridge: hipBridge,
                nearUpperArm: nearUpperArm,
                nearForearm: nearForearm,
                farUpperArm: farUpperArm,
                farForearm: farForearm,
                nearUpperLeg: nearUpperLeg,
                nearLowerLeg: nearLowerLeg,
                farUpperLeg: farUpperLeg,
                farLowerLeg: farLowerLeg,
                nearFoot: nearFoot,
                farFoot: farFoot,
                nearHand: nearHand,
                farHand: farHand,
                nearElbow: nearElbow,
                farElbow: farElbow,
                nearKnee: nearKnee,
                farKnee: farKnee,
                nearAnkle: nearAnkle,
                farAnkle: farAnkle
            )
        } catch {
            AvatarDiagnostics.logger.error("neutral_humanoid.glb failed to load: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func node(_ name: String, in root: SCNNode) -> SCNNode? {
        root.childNode(withName: name, recursively: true)
            ?? root.childNode(withName: name.replacingOccurrences(of: ".", with: "_"), recursively: true)
    }
}

private enum AvatarDiagnostics {
    static let logger = Logger(subsystem: "com.camifit.app", category: "avatar")
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

enum MotionDemoBundleStore {
    static func guideTimeline(for program: ExerciseProgram) -> MotionDemoTimeline? {
        timeline(for: program)
    }

    static func timeline(for program: ExerciseProgram) -> MotionDemoTimeline? {
        guard AppExerciseTrackingGate.guideReadyPresetIDs.contains(program.id) else {
            return nil
        }

        guard let url = AppResourceBundle.url(
            forResource: program.id,
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ) else {
            return nil
        }

        do {
            let decoded = try MediaPipePoseJSONLDecoder.decode(contentsOf: url)
            guard !decoded.isEmpty else { return nil }
            let frames = MotionDemoKeyframeSmoother.smooth(decoded)
            let duration = timelineDuration(for: frames)
            guard let manifest = MotionDemoManifest.load(nextTo: url) else {
                return nil
            }
            guard manifest.isGuideEligible(for: program.id) else { return nil }
            return MotionDemoTimeline(
                programID: program.id,
                programName: program.name,
                source: manifest.source(for: url),
                frames: frames,
                durationMS: duration
            )
        } catch {
            return nil
        }
    }

    private static func timelineDuration(for frames: [PoseFrame]) -> Int64 {
        guard let first = frames.first, let last = frames.last else { return 1 }
        guard frames.count > 1 else { return max(last.timestampMS, 1) }

        let intervals = zip(frames, frames.dropFirst())
            .map { max($1.timestampMS - $0.timestampMS, 0) }
            .filter { $0 > 0 }
        let fallbackInterval = intervals.first ?? 100
        let interval = intervals.isEmpty
            ? fallbackInterval
            : intervals.sorted()[intervals.count / 2]

        return posesMatch(first, last)
            ? max(last.timestampMS, interval)
            : max(last.timestampMS + interval, 1)
    }

    private static func posesMatch(_ first: PoseFrame, _ last: PoseFrame) -> Bool {
        let names = Set(first.landmarks.keys).intersection(last.landmarks.keys)
        guard !names.isEmpty else { return false }

        let maxDelta = names.reduce(Double(0)) { partial, name in
            guard let a = first.landmarks[name], let b = last.landmarks[name] else {
                return partial
            }
            return max(
                partial,
                abs(a.x - b.x),
                abs(a.y - b.y),
                abs(a.z - b.z)
            )
        }
        return maxDelta < 0.000_001
    }
}

struct MotionDemoManifest: Decodable {
    let exerciseID: String?
    let sourceKind: MotionDemoSourceKind?
    let sourceLabel: String?
    let acceptanceStatus: String?
    let playableTracePackaged: Bool
    let normalizerStatus: String?
    let rejectionReason: String?
    let sourcePage: String?
    let sourceURL: String?
    let sourceMediaURL: String?
    let sourceVideo: String?
    let sourceLicense: String?
    let sourceAttribution: String?
    let rawTrace: String?
    let normalizer: String?
    let outputTrace: String?
    let goldenComparison: GoldenComparison?
    let visualReview: VisualReview?
    let engineReplay: EngineReplay?
    let liveAppReview: LiveAppReview?
    let rejectedSources: RejectedSources?
    let rejectedCandidates: [RejectedCandidate]?

    private enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case sourceKind = "source_kind"
        case sourceLabel = "source_label"
        case acceptanceStatus = "acceptance_status"
        case playableTracePackaged = "playable_trace_packaged"
        case normalizerStatus = "normalizer_status"
        case rejectionReason = "rejection_reason"
        case sourcePage = "source_page"
        case sourceURL = "source_url"
        case sourceMediaURL = "source_media_url"
        case sourceVideo = "source_video"
        case sourceLicense = "source_license"
        case sourceAttribution = "source_attribution"
        case rawTrace = "raw_trace"
        case normalizer
        case outputTrace = "output_trace"
        case goldenComparison = "golden_comparison"
        case visualReview = "visual_review"
        case engineReplay = "engine_replay"
        case liveAppReview = "live_app_review"
        case rejectedSources = "rejected_sources"
        case rejectedCandidates = "rejected_candidates"
    }

    struct GoldenComparison: Decodable {
        let status: String?
        let reason: String?
        let goldenTrace: String?
        let candidateTrace: String?
        let comparisonReport: String?

        private enum CodingKeys: String, CodingKey {
            case status
            case reason
            case goldenTrace = "golden_trace"
            case candidateTrace = "candidate_trace"
            case comparisonReport = "comparison_report"
        }

        var isPromotionDecisionRecorded: Bool {
            let normalizedStatus = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch normalizedStatus {
            case "not_applicable":
                return reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            case "passed", "reviewed":
                return Self.hasText(goldenTrace)
                    && Self.hasText(candidateTrace)
                    && Self.hasText(comparisonReport)
            default:
                return false
            }
        }

        private static func hasText(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    struct VisualReview: Decodable {
        let status: String?
        let evidence: String?

        var isPassed: Bool {
            let normalizedStatus = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ["passed", "reviewed"].contains(normalizedStatus)
                && evidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    struct EngineReplay: Decodable {
        let status: String?
        let test: String?
        let actualFinalReps: Double?
        let actualHoldTargetReached: Bool?

        private enum CodingKeys: String, CodingKey {
            case status
            case test
            case actualFinalReps = "actual_final_reps"
            case actualHoldTargetReached = "actual_hold_target_reached"
        }

        var isPassed: Bool {
            let normalizedStatus = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalizedStatus == "passed"
                && test?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && (actualFinalReps != nil || actualHoldTargetReached != nil)
        }
    }

    struct LiveAppReview: Decodable {
        let status: String?
        let evidence: String?
        let appBundle: String?
        let installedPlayableJSONLs: Int?
        let installedPlayableTraceIDs: [String]?

        private enum CodingKeys: String, CodingKey {
            case status
            case evidence
            case appBundle = "app_bundle"
            case installedPlayableJSONLs = "installed_playable_jsonls"
            case installedPlayableTraceIDs = "installed_playable_trace_ids"
        }

        func isPassed(for exerciseID: String?) -> Bool {
            let normalizedStatus = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalizedIDs = installedPlayableTraceIDs?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
            let expectedExerciseID = exerciseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalizedStatus == "passed"
                && Self.hasText(evidence)
                && Self.hasText(appBundle)
                && (installedPlayableJSONLs ?? 0) > 0
                && installedPlayableJSONLs == normalizedIDs.count
                && !expectedExerciseID.isEmpty
                && normalizedIDs.contains(expectedExerciseID)
        }

        private static func hasText(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    struct RejectedSources: Decodable {
        let status: String?
        let reviewScope: String?
        let reason: String?

        private enum CodingKeys: String, CodingKey {
            case status
            case reviewScope = "review_scope"
            case reason
        }

        var isRecorded: Bool {
            let normalizedStatus = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [
                "none_retained_for_promotion_review",
                "none_rejected_after_review"
            ].contains(normalizedStatus)
                && Self.hasText(reviewScope)
                && Self.hasText(reason)
        }

        private static func hasText(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    struct RejectedCandidate: Decodable {
        let sourcePage: String?
        let sourceMediaURL: String?
        let sourceURL: String?
        let sourceVideo: String?
        let sourceLicense: String?
        let sourceAttribution: String?
        let decision: String?
        let reason: String?

        private enum CodingKeys: String, CodingKey {
            case sourcePage = "source_page"
            case sourceMediaURL = "source_media_url"
            case sourceURL = "source_url"
            case sourceVideo = "source_video"
            case sourceLicense = "source_license"
            case sourceAttribution = "source_attribution"
            case decision
            case reason
        }

        var isRejectedSourceRecord: Bool {
            let normalizedDecision = decision?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return hasSource
                && Self.hasText(sourceLicense)
                && Self.hasText(sourceAttribution)
                && normalizedDecision.contains("rejected")
                && Self.hasText(reason)
        }

        private var hasSource: Bool {
            [sourcePage, sourceMediaURL, sourceURL, sourceVideo].contains { Self.hasText($0) }
        }

        private static func hasText(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    init(
        exerciseID: String? = nil,
        sourceKind: MotionDemoSourceKind?,
        sourceLabel: String?,
        acceptanceStatus: String?,
        playableTracePackaged: Bool = false,
        normalizerStatus: String?,
        rejectionReason: String?,
        sourcePage: String? = nil,
        sourceURL: String? = nil,
        sourceMediaURL: String? = nil,
        sourceVideo: String? = nil,
        sourceLicense: String? = nil,
        sourceAttribution: String? = nil,
        rawTrace: String? = nil,
        normalizer: String? = nil,
        outputTrace: String? = nil,
        goldenComparison: GoldenComparison? = nil,
        visualReview: VisualReview? = nil,
        engineReplay: EngineReplay? = nil,
        liveAppReview: LiveAppReview? = nil,
        rejectedSources: RejectedSources? = nil,
        rejectedCandidates: [RejectedCandidate] = []
    ) {
        self.exerciseID = exerciseID
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
        self.acceptanceStatus = acceptanceStatus
        self.playableTracePackaged = playableTracePackaged
        self.normalizerStatus = normalizerStatus
        self.rejectionReason = rejectionReason
        self.sourcePage = sourcePage
        self.sourceURL = sourceURL
        self.sourceMediaURL = sourceMediaURL
        self.sourceVideo = sourceVideo
        self.sourceLicense = sourceLicense
        self.sourceAttribution = sourceAttribution
        self.rawTrace = rawTrace
        self.normalizer = normalizer
        self.outputTrace = outputTrace
        self.goldenComparison = goldenComparison
        self.visualReview = visualReview
        self.engineReplay = engineReplay
        self.liveAppReview = liveAppReview
        self.rejectedSources = rejectedSources
        self.rejectedCandidates = rejectedCandidates
    }

    static func load(nextTo traceURL: URL) -> MotionDemoManifest? {
        let manifestURL = traceURL
            .deletingPathExtension()
            .appendingPathExtension("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(MotionDemoManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    var isGuideEligible: Bool {
        if rejectionReason?.isEmpty == false {
            return false
        }

        for status in [acceptanceStatus, normalizerStatus].compactMap({ $0?.lowercased() }) {
            if status.contains("pending") || status.contains("required") || status.contains("rejected") {
                return false
            }
        }

        let acceptedStatus = acceptanceStatus?.lowercased() ?? ""
        guard acceptedStatus.hasPrefix("accepted") || acceptedStatus.hasPrefix("protected_golden") else {
            return false
        }
        guard playableTracePackaged else {
            return false
        }
        guard hasText(sourceLabel),
              hasText(sourceVideo),
              hasText(sourceLicense),
              hasText(sourceAttribution),
              hasText(rawTrace),
              hasText(normalizer),
              hasText(outputTrace),
              goldenComparison?.isPromotionDecisionRecorded == true,
              visualReview?.isPassed == true,
              engineReplay?.isPassed == true,
              liveAppReview?.isPassed(for: exerciseID) == true else {
            return false
        }

        switch sourceKind {
        case .trainerReferenceTrace:
            return true
        case .licensedExternalReferenceTrace:
            return hasText(sourcePage) && hasText(sourceMediaURL) && hasRejectedSourceReview
        case .canonicalArchetypeTrace, .proceduralFallback, .none:
            return false
        }
    }

    func isGuideEligible(for programID: String) -> Bool {
        let normalizedManifestID = exerciseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProgramID = programID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedManifestID.isEmpty
            && normalizedManifestID == normalizedProgramID
            && isGuideEligible
    }

    private var hasRejectedSourceReview: Bool {
        if rejectedCandidates?.contains(where: { $0.isRejectedSourceRecord }) == true {
            return true
        }
        return rejectedSources?.isRecorded == true
    }

    private func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func source(for traceURL: URL) -> MotionDemoSource {
        let label = sourceLabel.map { "\($0): \(traceURL.lastPathComponent)" }
            ?? traceURL.lastPathComponent
        switch sourceKind {
        case .canonicalArchetypeTrace:
            return .canonicalArchetypeTrace(provenance: "Bundled canonical archetype trace: \(label)")
        case .trainerReferenceTrace, .licensedExternalReferenceTrace, .proceduralFallback, .none:
            return .trainerReferenceTrace(provenance: "Bundled reference trace: \(label)")
        }
    }
}
