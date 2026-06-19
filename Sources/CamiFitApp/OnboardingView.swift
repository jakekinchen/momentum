import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    nonisolated static let completedStorageKey = "camifit.onboarding.completed"
    nonisolated static let completedVersionStorageKey = "camifit.onboarding.completedVersion"
    nonisolated static let currentVersion = 2

    @Published var isPresented = false

    func showTour() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

enum CamiFitOnboardingStepID: String, CaseIterable {
    case movement
    case engine
    case coach
    case memory
    case privacy
}

struct CamiFitOnboardingStep: Identifiable, Equatable {
    let id: CamiFitOnboardingStepID
    let eyebrow: String
    let title: String
    let summary: String
    let bullets: [String]
    let systemImage: String

    static let all: [CamiFitOnboardingStep] = [
        CamiFitOnboardingStep(
            id: .movement,
            eyebrow: "Live movement",
            title: "Your camera becomes a rep tracker",
            summary: "\(ProductBrand.fullName) reads pose landmarks locally, draws the live skeleton, and turns movement into reps, holds, cues, and form feedback.",
            bullets: [
                "Live Camera uses the selected webcam in the main session viewer.",
                "Demo replays a bundled sample so the loop is visible without a camera.",
                "The HUD separates reps, timed holds, form score, and current cue."
            ],
            systemImage: "figure.strengthtraining.functional"
        ),
        CamiFitOnboardingStep(
            id: .engine,
            eyebrow: "Exercise engine",
            title: "Programs are executable rules",
            summary: "Every exercise is a small program. Pose frames become signals, signals pass through rules, and the engine emits countable progress.",
            bullets: [
                "Presets define signals, rep phases, hold targets, and form cues.",
                "Generated exercises are decoded and dry-run validated before saving.",
                "Invalid or low-confidence pose data fails closed instead of counting."
            ],
            systemImage: "slider.horizontal.3"
        ),
        CamiFitOnboardingStep(
            id: .coach,
            eyebrow: "Coach panel",
            title: "Chat can produce routines you can run",
            summary: "The coach answers questions, explains form, and can attach structured Momentum routine cards with a Start routine action.",
            bullets: [
                "Connect your OpenAI account in Settings to enable coach replies.",
                "Routine cards keep generated plans separate from normal chat text.",
                "Starting a routine selects each exercise block inside the app loop."
            ],
            systemImage: "bubble.left.and.bubble.right.fill"
        ),
        CamiFitOnboardingStep(
            id: .memory,
            eyebrow: "Memory and safety",
            title: "Health constraints stay visible",
            summary: "The memory inspector shows what \(ProductBrand.fullName) remembers, where it came from, and whether a later correction changed it.",
            bullets: [
                "Memory proposals are validated by the app before they are saved.",
                "Corrections append a new operation instead of rewriting history.",
                "Safety-facing graph state is separate from coach wording."
            ],
            systemImage: "brain.head.profile"
        ),
        CamiFitOnboardingStep(
            id: .privacy,
            eyebrow: "Local-first state",
            title: "The app owns the workout state on this Mac",
            summary: "Camera tracking, exercise execution, presets, and the member graph overlay live in app-owned local state. The coach verbalizes; deterministic app code decides what can run.",
            bullets: [
                "Coach threads live under Application Support, not a throwaway temp path.",
                "Member graph overlays are append-only local JSONL operations.",
                "The engine can run without sending pose frames to a model service."
            ],
            systemImage: "externaldrive.badge.checkmark"
        )
    ]
}

struct OnboardingFlowView: View {
    @State private var selection: CamiFitOnboardingStepID = .movement

    let onFinish: () -> Void

    private let steps = CamiFitOnboardingStep.all

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                OnboardingStepRail(steps: steps, selection: $selection)
                    .frame(width: 224)

                Divider()

                ScrollView {
                    OnboardingStepDetail(step: selectedStep)
                        .padding(26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.regularMaterial)
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 560, idealHeight: 610)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectedStep: CamiFitOnboardingStep {
        steps.first { $0.id == selection } ?? steps[0]
    }

    private var selectedIndex: Int {
        steps.firstIndex { $0.id == selection } ?? 0
    }

    private var isLastStep: Bool {
        selectedIndex == steps.count - 1
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                onFinish()
            } label: {
                Label("Skip Tour", systemImage: "xmark")
            }
            .buttonStyle(.bordered)

            Spacer()

            OnboardingProgressDots(count: steps.count, index: selectedIndex)

            Spacer()

            Button {
                moveSelection(by: -1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(selectedIndex == 0)

            Button {
                if isLastStep {
                    onFinish()
                } else {
                    moveSelection(by: 1)
                }
            } label: {
                Label(isLastStep ? "Start Momentum" : "Next",
                      systemImage: isLastStep ? "checkmark.circle.fill" : "chevron.right")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func moveSelection(by delta: Int) {
        let nextIndex = min(max(selectedIndex + delta, 0), steps.count - 1)
        withAnimation(.snappy(duration: 0.22)) {
            selection = steps[nextIndex].id
        }
    }
}

private struct OnboardingStepRail: View {
    let steps: [CamiFitOnboardingStep]
    @Binding var selection: CamiFitOnboardingStepID

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                BrandLogoMark()
                    .frame(width: 22, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ProductBrand.fullName)
                        .font(.headline.weight(.semibold))
                    Text("Feature tour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            VStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = step.id
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: step.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(step.eyebrow)")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Text(step.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selection == step.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        }
                    }
                    .overlay {
                        if selection == step.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .background(.regularMaterial)
    }
}

private struct OnboardingStepDetail: View {
    let step: CamiFitOnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingFeatureVisual(stepID: step.id)
                .frame(height: 250)

            VStack(alignment: .leading, spacing: 9) {
                Label(step.eyebrow, systemImage: step.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(step.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.summary)
                    .font(.system(size: 14.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(step.bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.green)
                        Text(bullet)
                            .font(.system(size: 13.5, weight: .regular, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingFeatureVisual: View {
    let stepID: CamiFitOnboardingStepID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.045, green: 0.055, blue: 0.075),
                            Color(red: 0.075, green: 0.12, blue: 0.11),
                            Color(red: 0.10, green: 0.075, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch stepID {
            case .movement:
                MovementTrackingVisual()
            case .engine:
                EngineRuleVisual()
            case .coach:
                CoachRoutineVisual()
            case .memory:
                MemoryGraphVisual()
            case .privacy:
                LocalStateVisual()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MovementTrackingVisual: View {
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    VisualPill("Camera", systemImage: "video.fill", tint: .cyan)
                    Spacer()
                    VisualPill("Pose", systemImage: "figure.walk.motion", tint: .mint)
                }
                Spacer()
                TimelineView(.animation) { timeline in
                    let movement = OnboardingMovementState(date: timeline.date)
                    HStack(spacing: 9) {
                        MetricChip(
                            label: "Reps",
                            value: "\(movement.repCount)",
                            color: .orange,
                            success: movement.successGlow
                        )
                        MetricChip(label: "Hold", value: movement.holdText, color: .blue)
                        MetricChip(label: "Cue", value: "steady", color: .green)
                    }
                }
            }
            .padding(18)

            PoseFigure()
                .frame(width: 142, height: 138)
                .offset(y: -30)
        }
    }
}

private struct OnboardingMovementState {
    private static let cycleDuration: TimeInterval = 2.35
    private static let cycleCount = 9

    let repCount: Int
    let holdText: String
    let squatDepth: CGFloat
    let successGlow: CGFloat

    init(date: Date) {
        let totalDuration = Self.cycleDuration * Double(Self.cycleCount)
        let loopElapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        let rawCycleIndex = Int(loopElapsed / Self.cycleDuration)
        let cycleIndex = min(Self.cycleCount - 1, max(0, rawCycleIndex))
        let cycleElapsed = loopElapsed - Double(cycleIndex) * Self.cycleDuration
        let phase = CGFloat(cycleElapsed / Self.cycleDuration)

        let countedIndex = min(Self.cycleCount - 1, cycleIndex + (phase >= 0.90 ? 1 : 0))
        repCount = 12 + countedIndex
        holdText = "0:\(30 - countedIndex)"

        if phase < 0.42 {
            squatDepth = Self.smoothstep(phase / 0.42)
        } else if phase < 0.52 {
            squatDepth = 1
        } else if phase < 0.90 {
            squatDepth = 1 - Self.smoothstep((phase - 0.52) / 0.38)
        } else {
            squatDepth = 0
        }

        let peakGlow: CGFloat = 0.52
        let returnGlow = phase < 0.52 ? 0 : Self.smoothstep((phase - 0.52) / 0.48) * peakGlow
        let releaseGlow = phase < 0.48 ? (1 - Self.smoothstep(phase / 0.48)) * peakGlow : 0
        successGlow = max(returnGlow, releaseGlow)
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private struct EngineRuleVisual: View {
    private let steps = [
        EnginePipelineStep(title: "Pose frame", subtitle: "camera frame", color: .cyan),
        EnginePipelineStep(title: "Signals", subtitle: "angles and filters", color: .mint),
        EnginePipelineStep(title: "Rules", subtitle: "phase + form", color: .orange),
        EnginePipelineStep(title: "Progress", subtitle: "rep, hold, cue", color: .pink)
    ]

    var body: some View {
        VStack(spacing: 9) {
            EnginePipelineRow(left: steps[0], right: steps[1])

            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "arrow.down.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.50))
                    .frame(width: 24, height: 14)
                Spacer()
            }
            .frame(height: 14)

            EnginePipelineRow(left: steps[2], right: steps[3])

            EngineFailClosedCallout()
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct EnginePipelineStep {
    let title: String
    let subtitle: String
    let color: Color
}

private struct EnginePipelineRow: View {
    let left: EnginePipelineStep
    let right: EnginePipelineStep

    var body: some View {
        HStack(spacing: 12) {
            FlowNode(title: left.title, subtitle: left.subtitle, color: left.color)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 16)

            FlowNode(title: right.title, subtitle: right.subtitle, color: right.color)
        }
    }
}

private struct CoachRoutineVisual: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ChatBubblePreview(text: "How should I train today?", isUser: true)
                ChatBubblePreview(text: "Here is a knee-aware routine.", isUser: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BrandLogoMark()
                        .frame(width: 18, height: 24)
                    Text("Routine")
                        .font(.headline.weight(.semibold))
                }
                Text("Warm-up")
                Text("Main set")
                Text("Cooldown")
                Button {} label: {
                    Label("Start routine", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(16)
            .frame(width: 190, alignment: .leading)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(22)
    }
}

private struct MemoryGraphVisual: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MemoryFlowColumn(title: "Input", caption: "User-owned facts") {
                VStack(spacing: 10) {
                    MemoryFlowCard(title: "Left knee", subtitle: "health note", systemImage: "figure.walk", tint: .orange)
                    MemoryFlowCard(title: "Correction", subtitle: "new operation", systemImage: "arrow.triangle.2.circlepath", tint: .cyan)
                }
            }
            .frame(width: 118)

            MemoryMergeConnector()
                .frame(width: 28, height: 132)

            MemoryFlowColumn(title: "Reliable Recall", caption: "Validated memory") {
                MemoryFlowCard(title: "Memory recording", subtitle: "Personalized knowledge graph", systemImage: "list.bullet.clipboard", tint: .mint, height: 86)
            }
            .frame(width: 118)

            MemoryArrowConnector()
                .frame(width: 22, height: 132)

            MemoryFlowColumn(title: "Decision", caption: "Workout filter") {
                MemoryFlowCard(title: "Safety gate", subtitle: "allow or avoid", systemImage: "checkmark.shield.fill", tint: .green, height: 86)
            }
            .frame(width: 118)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
    }
}

private struct LocalStateVisual: View {
    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: "macbook")
                    .font(.system(size: 58, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                Text("On this Mac")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 170)

            VStack(alignment: .leading, spacing: 10) {
                LocalStateRow(title: "Pose frames", subtitle: "processed locally", systemImage: "figure.run", color: .cyan)
                LocalStateRow(title: "Exercise engine", subtitle: "deterministic rules", systemImage: "gearshape.2.fill", color: .orange)
                LocalStateRow(title: "Member overlay", subtitle: "Application Support JSONL", systemImage: "externaldrive.fill", color: .green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }
}

private struct PoseFigure: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let movement = OnboardingMovementState(date: timeline.date)

            Canvas { context, size in
                let pose = OnboardingPoseFrame(canvasSize: size, squat: movement.squatDepth)

                drawMotionEchoes(in: context, size: size, squat: movement.squatDepth)
                drawMannequin(in: context, pose: pose, success: movement.successGlow)
                drawSkeleton(in: context, pose: pose, lineOpacity: 0.94, jointOpacity: 1)
            }
        }
        .shadow(color: .mint.opacity(0.45), radius: 14)
    }

    private func drawMotionEchoes(in context: GraphicsContext, size: CGSize, squat: CGFloat) {
        for offset in [-0.20, 0.20] {
            let ghostSquat = min(max(squat + CGFloat(offset), 0), 1)
            let pose = OnboardingPoseFrame(canvasSize: size, squat: ghostSquat)
            drawSkeleton(in: context, pose: pose, lineOpacity: 0.16, jointOpacity: 0, lineWidth: 2)
        }
    }

    private func drawMannequin(in context: GraphicsContext, pose: OnboardingPoseFrame, success: CGFloat) {
        let fill = Color.white.opacity(0.12)
        let successFill = Color.green.opacity(0.62 * Double(success))
        let edge = Color.white.opacity(0.16)
        let successEdge = Color.green.opacity(0.50 * Double(success))

        context.fill(
            Path(ellipseIn: CGRect(
                x: pose.head.x - pose.headRadius,
                y: pose.head.y - pose.headRadius,
                width: pose.headRadius * 2,
                height: pose.headRadius * 2
            )),
            with: .color(fill)
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: pose.head.x - pose.headRadius,
                y: pose.head.y - pose.headRadius,
                width: pose.headRadius * 2,
                height: pose.headRadius * 2
            )),
            with: .color(successFill)
        )

        strokeMannequinLine(
            in: context,
            points: [pose.neck, pose.midHip],
            color: fill,
            width: pose.bodyStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.neck, pose.midHip],
            color: successFill,
            width: pose.bodyStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftShoulder, pose.neck, pose.rightShoulder, pose.rightHip, pose.leftHip, pose.leftShoulder],
            color: fill.opacity(0.7),
            width: pose.torsoStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftShoulder, pose.leftElbow, pose.leftWrist],
            color: fill,
            width: pose.limbStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.rightShoulder, pose.rightElbow, pose.rightWrist],
            color: fill,
            width: pose.limbStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftHip, pose.leftKnee, pose.leftAnkle],
            color: fill,
            width: pose.legStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.rightHip, pose.rightKnee, pose.rightAnkle],
            color: fill,
            width: pose.legStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftShoulder, pose.leftElbow, pose.leftWrist],
            color: successFill,
            width: pose.limbStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.rightShoulder, pose.rightElbow, pose.rightWrist],
            color: successFill,
            width: pose.limbStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftHip, pose.leftKnee, pose.leftAnkle],
            color: successFill,
            width: pose.legStrokeWidth
        )
        strokeMannequinLine(
            in: context,
            points: [pose.rightHip, pose.rightKnee, pose.rightAnkle],
            color: successFill,
            width: pose.legStrokeWidth
        )

        strokeMannequinLine(
            in: context,
            points: [pose.leftShoulder, pose.neck, pose.rightShoulder, pose.rightHip, pose.leftHip, pose.leftShoulder],
            color: edge,
            width: 1.4
        )
        strokeMannequinLine(
            in: context,
            points: [pose.leftShoulder, pose.neck, pose.rightShoulder, pose.rightHip, pose.leftHip, pose.leftShoulder],
            color: successEdge,
            width: 1.4 + 0.8 * success
        )
    }

    private func strokeMannequinLine(
        in context: GraphicsContext,
        points: [CGPoint],
        color: Color,
        width: CGFloat
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSkeleton(
        in context: GraphicsContext,
        pose: OnboardingPoseFrame,
        lineOpacity: Double,
        jointOpacity: Double,
        lineWidth: CGFloat = 3.2
    ) {
        var skeleton = Path()
        for segment in OnboardingPoseFrame.segments {
            skeleton.move(to: pose.points[segment.0])
            skeleton.addLine(to: pose.points[segment.1])
        }
        context.stroke(
            skeleton,
            with: .color(Color.mint.opacity(lineOpacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )

        guard jointOpacity > 0 else { return }
        for point in pose.points {
            let rect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(jointOpacity)))
        }
    }
}

private struct OnboardingPoseFrame {
    static let segments = [
        (0, 1),
        (1, 2), (1, 3),
        (2, 4), (3, 5),
        (1, 6), (1, 7),
        (6, 8), (8, 10),
        (7, 9), (9, 11)
    ]

    let head: CGPoint
    let neck: CGPoint
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftWrist: CGPoint
    let rightWrist: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint
    let leftKnee: CGPoint
    let rightKnee: CGPoint
    let leftAnkle: CGPoint
    let rightAnkle: CGPoint
    let scale: CGFloat

    var headRadius: CGFloat {
        scale * 0.105
    }

    var bodyStrokeWidth: CGFloat {
        scale * 0.16
    }

    var torsoStrokeWidth: CGFloat {
        scale * 0.10
    }

    var limbStrokeWidth: CGFloat {
        scale * 0.12
    }

    var legStrokeWidth: CGFloat {
        scale * 0.14
    }

    var midHip: CGPoint {
        CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
    }

    var leftElbow: CGPoint {
        midpoint(leftShoulder, leftWrist)
    }

    var rightElbow: CGPoint {
        midpoint(rightShoulder, rightWrist)
    }

    var points: [CGPoint] {
        [
            head,
            neck,
            leftShoulder,
            rightShoulder,
            leftWrist,
            rightWrist,
            leftHip,
            rightHip,
            leftKnee,
            rightKnee,
            leftAnkle,
            rightAnkle
        ]
    }

    init(canvasSize: CGSize, squat: CGFloat) {
        let bounds = CGRect(
            x: canvasSize.width * 0.10,
            y: canvasSize.height * 0.12,
            width: canvasSize.width * 0.80,
            height: canvasSize.height * 0.76
        )
        scale = bounds.width

        let down = squat * 0.10
        let kneeBend = squat * 0.09
        let reach = squat * 0.04

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.minX + bounds.width * x, y: bounds.minY + bounds.height * y)
        }

        head = point(0.50, 0.08 + down * 0.55)
        neck = point(0.50, 0.24 + down * 0.72)
        leftShoulder = point(0.35, 0.34 + down * 0.64)
        rightShoulder = point(0.65, 0.34 + down * 0.64)
        leftWrist = point(0.28 - reach, 0.55 + down * 0.25)
        rightWrist = point(0.72 + reach, 0.55 + down * 0.25)
        leftHip = point(0.43, 0.56 + down)
        rightHip = point(0.57, 0.56 + down)
        leftKnee = point(0.36 - kneeBend, 0.76 + down * 0.32)
        rightKnee = point(0.64 + kneeBend, 0.76 + down * 0.32)
        leftAnkle = point(0.34, 0.94)
        rightAnkle = point(0.66, 0.94)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

private struct VisualPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.36), lineWidth: 1))
    }
}

private struct MetricChip: View {
    let label: String
    let value: String
    let color: Color
    var success: CGFloat = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(width: 76, height: 50)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.24 * Double(success)))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.green.opacity(0.34 * Double(success)), lineWidth: 1.2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .green.opacity(0.14 * Double(success)), radius: 7 * success, y: 2)
    }
}

private struct FlowNode: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.78))
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.10))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct EngineFailClosedCallout: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Fail closed")
                    .font(.caption.weight(.semibold))
                Text("Low-confidence pose data never becomes a counted rep.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 360, minHeight: 44, alignment: .leading)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct ChatBubblePreview: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 30) }
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isUser ? Color.blue.opacity(0.42) : Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !isUser { Spacer(minLength: 30) }
        }
    }
}

private struct MemoryFlowColumn<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            content
                .frame(height: 132, alignment: .center)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(height: 30)
        }
        .frame(height: 172, alignment: .top)
    }
}

private struct MemoryFlowCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(subtitle)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.048, green: 0.055, blue: 0.067))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.40))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(tint.opacity(0.62), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 8, y: 4)
    }
}

private struct MemoryMergeConnector: View {
    var body: some View {
        Canvas { context, size in
            let startX: CGFloat = 1
            let mergeX = size.width * 0.50
            let endX = size.width - 2
            let topY = size.height * 0.36
            let bottomY = size.height * 0.64
            let midY = size.height * 0.50

            var path = Path()
            path.move(to: CGPoint(x: startX, y: topY))
            path.addQuadCurve(to: CGPoint(x: mergeX, y: midY),
                              control: CGPoint(x: mergeX * 0.42, y: topY))
            path.move(to: CGPoint(x: startX, y: bottomY))
            path.addQuadCurve(to: CGPoint(x: mergeX, y: midY),
                              control: CGPoint(x: mergeX * 0.42, y: bottomY))
            path.move(to: CGPoint(x: mergeX, y: midY))
            path.addLine(to: CGPoint(x: endX, y: midY))
            context.stroke(path, with: .color(.mint.opacity(0.72)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [6, 6]))

            drawArrow(context: &context,
                      tip: CGPoint(x: endX, y: midY),
                      angle: 0,
                      color: .mint)

            context.fill(Path(ellipseIn: CGRect(x: mergeX - 3, y: midY - 3, width: 6, height: 6)),
                         with: .color(.mint.opacity(0.86)))
        }
        .allowsHitTesting(false)
    }
}

private struct MemoryArrowConnector: View {
    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.50
            let endX = size.width - 2
            var path = Path()
            path.move(to: CGPoint(x: 1, y: midY))
            path.addLine(to: CGPoint(x: endX, y: midY))
            context.stroke(path, with: .color(.green.opacity(0.74)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 6]))
            drawArrow(context: &context,
                      tip: CGPoint(x: endX, y: midY),
                      angle: 0,
                      color: .green)
        }
        .allowsHitTesting(false)
    }
}

private func drawArrow(context: inout GraphicsContext, tip: CGPoint, angle: CGFloat, color: Color) {
    let length: CGFloat = 7
    let spread: CGFloat = .pi / 6
    var arrow = Path()
    arrow.move(to: tip)
    arrow.addLine(to: CGPoint(x: tip.x - length * cos(angle - spread),
                              y: tip.y - length * sin(angle - spread)))
    arrow.move(to: tip)
    arrow.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread),
                              y: tip.y - length * sin(angle + spread)))
    context.stroke(arrow, with: .color(color.opacity(0.86)),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
}

private struct LocalStateRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct OnboardingProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Color.accentColor : Color.secondary.opacity(0.26))
                    .frame(width: dot == index ? 18 : 7, height: 7)
                    .animation(.snappy(duration: 0.18), value: index)
            }
        }
        .accessibilityLabel("Onboarding step \(index + 1) of \(count)")
    }
}
