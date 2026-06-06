import CamiFitEngine
import SwiftUI

@MainActor
final class FormCheckController: ObservableObject {
    @Published private(set) var isActive = false

    private var baselineRepCount = 0
    private var baselineHoldSeconds = 0.0

    func toggle(current state: AppExerciseSessionState) {
        isActive ? cancel() : begin(current: state)
    }

    func begin(current state: AppExerciseSessionState) {
        baselineRepCount = state.repCount
        baselineHoldSeconds = state.holdSeconds
        withAnimation(.smooth(duration: 0.28)) {
            isActive = true
        }
    }

    func cancel() {
        withAnimation(.smooth(duration: 0.22)) {
            isActive = false
        }
    }

    func progress(for state: AppExerciseSessionState, target: SetTarget?) -> Double {
        guard isActive else { return 0 }

        switch target {
        case .reps:
            return state.repCount > baselineRepCount ? 1 : 0
        case let .holdSeconds(seconds):
            let matchWindow = min(max(seconds, 1), 3)
            return Self.clamp((state.holdSeconds - baselineHoldSeconds) / matchWindow)
        case .none:
            if state.repCount > baselineRepCount || state.holdTargetReached {
                return 1
            }
            return Self.clamp(state.holdSeconds - baselineHoldSeconds)
        }
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

enum TrainingTimelineStage: String, Equatable {
    case warmup = "Warm-up"
    case work = "Work"
    case cooldown = "Cool-down"

    var tint: Color {
        switch self {
        case .warmup: .cyan
        case .work: .mint
        case .cooldown: .blue
        }
    }

    static func classify(title: String, exerciseID: String? = nil) -> TrainingTimelineStage {
        let haystack = "\(title) \(exerciseID ?? "")".lowercased()
        if haystack.contains("warm") ||
            haystack.contains("march") ||
            haystack.contains("mobility") ||
            haystack.contains("circle") ||
            haystack.contains("activation") {
            return .warmup
        }
        if haystack.contains("cool") ||
            haystack.contains("stretch") ||
            haystack.contains("breath") ||
            haystack.contains("recovery") {
            return .cooldown
        }
        return .work
    }
}

enum TrainingTimelineStepState: Equatable {
    case complete
    case current
    case upcoming

    var symbol: String {
        switch self {
        case .complete: "checkmark"
        case .current: "circle.fill"
        case .upcoming: "circle"
        }
    }
}

struct TrainingTimelineStep: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let stage: TrainingTimelineStage
    let state: TrainingTimelineStepState
}

struct TrainingContextPanel: View {
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @ObservedObject var formCheck: FormCheckController
    @State private var actionError: String?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header

                ExerciseTimeline(steps: exerciseTimelineSteps, onSelect: handleTimelineStep)

                if let nextExerciseTitle = routineRunner.nextExerciseTitle {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(nextExerciseTitle)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 10)

                        Button {
                            formCheck.cancel()
                            routineRunner.skipToNextExercise()
                            actionError = nil
                        } label: {
                            Label("Next Exercise", systemImage: "forward.end.fill")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let actionError {
                    Text(actionError)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 2)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contextTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    TrainingContextPill(systemImage: phaseSymbol, text: phaseText, tint: phaseTint)
                    if let guideDemoText {
                        TrainingContextPill(systemImage: "play.circle.fill", text: guideDemoText, tint: .cyan, fillOpacity: 0.12, strokeOpacity: 0.22)
                    }
                    if let routineContextText {
                        TrainingContextPill(systemImage: "music.note.list", text: routineContextText, tint: .secondary, fillOpacity: 0.08, strokeOpacity: 0.12)
                    }
                    if let targetText {
                        TrainingContextPill(systemImage: "target", text: targetText, tint: .secondary, fillOpacity: 0.08, strokeOpacity: 0.12)
                    }
                    if let guideSetupText {
                        TrainingContextPill(systemImage: "camera.viewfinder", text: guideSetupText, tint: .secondary, fillOpacity: 0.08, strokeOpacity: 0.12)
                    }
                }
            }

            Spacer(minLength: 10)

            Button {
                toggleFormMatch()
            } label: {
                Label(formCheck.isActive ? "Matching" : "Match Form", systemImage: formCheck.isActive ? "checkmark.circle.fill" : "scope")
            }
            .buttonStyle(.glassProminent)
            .tint(formCheck.isActive ? .green : .mint)
            .disabled(model.activeExerciseProgram == nil)
            .help("Overlay the target form for the active exercise")
        }
    }

    private var contextTitle: String {
        if let block = routineRunner.currentBlock {
            return block.title
        }
        return model.state.selectedExerciseName ?? "Training"
    }

    private var routineContextText: String? {
        guard routineRunner.isRoutineBackedRun, let routine = routineRunner.currentRoutine else { return nil }
        return routine.name
    }

    private var phaseText: String {
        if routineRunner.phase.isActive || routineRunner.isPaused {
            return routinePhaseText
        }
        if formCheck.isActive {
            return "Form match"
        }
        return "Ready"
    }

    private var routinePhaseText: String {
        switch routineRunner.phase {
        case .idle:
            return "Ready"
        case .preparing:
            return "Starting"
        case .guide:
            return "Guide"
        case .awaitingCamera:
            return "Camera"
        case .awaitingPose:
            return "Pose"
        case .countdown:
            return "Countdown"
        case .working:
            return "Working"
        case .rest:
            return "Rest"
        case .paused:
            return "Paused"
        case .complete:
            return "Complete"
        case .failed:
            return "Needs attention"
        }
    }

    private var phaseSymbol: String {
        switch routineRunner.phase {
        case .working: "figure.run"
        case .guide: "figure.strengthtraining.functional"
        case .rest: "timer"
        case .paused: "pause.fill"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: formCheck.isActive ? "scope" : "bolt.fill"
        }
    }

    private var phaseTint: Color {
        switch routineRunner.phase {
        case .working: .green
        case .guide, .countdown, .preparing: .cyan
        case .rest, .paused: .orange
        case .complete: .green
        case .failed: .red
        default: formCheck.isActive ? .green : .secondary
        }
    }

    private var targetText: String? {
        if let target = currentTarget {
            return target.displayText
        }
        return nil
    }

    private var guideDemoText: String? {
        guard case let .guide(secondsRemaining) = routineRunner.phase else { return nil }
        return "\(secondsRemaining)s demo"
    }

    private var guideSetupText: String? {
        guard routineRunner.phase.usesGuide else { return nil }
        return currentPresentationSummary?.setupText
    }

    private var currentPresentationSummary: ExercisePresentationSummary? {
        guard let program = currentProgram else { return nil }
        return RoutinePresentation.summary(for: program)
    }

    private var currentProgram: ExerciseProgram? {
        if let block = routineRunner.currentBlock {
            return block.program
        }
        return model.activeExerciseProgram
    }

    private var currentTarget: SetTarget? {
        if let target = routineRunner.currentSet?.target {
            return target
        }
        guard let program = model.activeExerciseProgram else { return nil }
        return SetTarget.defaultTarget(for: program)
    }

    private var exerciseTimelineSteps: [TrainingTimelineStep] {
        let isMatched = formCheck.progress(for: model.state, target: currentTarget) >= 1
        let phase = routineRunner.phase
        let isRoutineActive = routineRunner.currentRoutine != nil && phase.isActive
        let workStage = currentExerciseStage
        let guideState: TrainingTimelineStepState
        if isRoutineActive {
            switch phase {
            case .preparing, .guide:
                guideState = .current
            default:
                guideState = .complete
            }
        } else {
            guideState = formCheck.isActive || isMatched || hasStandaloneProgress ? .complete : .current
        }

        let matchState: TrainingTimelineStepState
        if isMatched {
            matchState = .complete
        } else if formCheck.isActive {
            matchState = .current
        } else {
            matchState = .upcoming
        }

        let workState: TrainingTimelineStepState
        switch phase {
        case .working:
            workState = .current
        case .rest, .complete:
            workState = .complete
        default:
            workState = isMatched || hasStandaloneProgress ? .current : .upcoming
        }

        let finishState: TrainingTimelineStepState
        switch phase {
        case .rest, .complete:
            finishState = .current
        default:
            finishState = .upcoming
        }

        return [
            TrainingTimelineStep(id: 0, title: "Guide", detail: guideDemoText ?? "Demo", stage: .warmup, state: guideState),
            TrainingTimelineStep(id: 1, title: "Match", detail: "Form", stage: .work, state: matchState),
            TrainingTimelineStep(id: 2, title: workTitle(for: workStage), detail: workDetail, stage: workStage, state: workState),
            TrainingTimelineStep(id: 3, title: "Finish", detail: finishDetail, stage: .cooldown, state: finishState)
        ]
    }

    private var currentExerciseStage: TrainingTimelineStage {
        if let block = routineRunner.currentBlock {
            return TrainingTimelineStage.classify(title: block.title, exerciseID: block.program.id)
        }
        guard let program = model.activeExerciseProgram else { return .work }
        return TrainingTimelineStage.classify(title: program.name, exerciseID: program.id)
    }

    private var hasStandaloneProgress: Bool {
        !routineRunner.phase.isActive && (model.state.repCount > 0 || model.state.holdSeconds > 0)
    }

    private var workDetail: String {
        if let setText = routineRunner.setText {
            return setText
        }
        return currentTarget?.displayText ?? "Set"
    }

    private var finishDetail: String {
        if case .rest = routineRunner.phase {
            return "Rest"
        }
        return "Summary"
    }

    private func workTitle(for stage: TrainingTimelineStage) -> String {
        switch stage {
        case .warmup:
            return "Warm Up"
        case .work:
            return "Work"
        case .cooldown:
            return "Cool Down"
        }
    }

    private func handleTimelineStep(_ step: TrainingTimelineStep) {
        withAnimation(.smooth(duration: 0.24)) {
            actionError = nil

            switch step.id {
            case 0:
                formCheck.cancel()
                if routineRunner.currentRoutine != nil {
                    routineRunner.replayGuide()
                } else {
                    startSelectedExercise(mode: .guide)
                }
            case 1:
                beginFormMatch()
            case 2:
                formCheck.cancel()
                jumpToWork()
            case 3:
                formCheck.cancel()
                jumpToFinish()
            default:
                break
            }
        }
    }

    private func toggleFormMatch() {
        if formCheck.isActive {
            formCheck.cancel()
        } else {
            beginFormMatch()
        }
    }

    private func beginFormMatch() {
        if routineRunner.isGuideOnlyExerciseRun {
            routineRunner.startCurrentExercisePractice()
        } else if shouldStartSelectedExerciseFromTimeline {
            guard startSelectedExercise(mode: .matchForm, skipsGuide: true) else { return }
        }
        formCheck.begin(current: model.state)
    }

    private func jumpToWork() {
        switch routineRunner.phase {
        case .idle, .complete, .failed:
            startSelectedExercise(mode: .camera, skipsGuide: true)
        case .preparing, .guide:
            routineRunner.skipGuide()
        case .rest:
            routineRunner.skipRest()
        case let .paused(previous):
            routineRunner.resume()
            switch previous {
            case .preparing, .guide:
                routineRunner.skipGuide()
            case .rest:
                routineRunner.skipRest()
            case .awaitingCamera, .awaitingPose, .countdown, .working:
                break
            }
        case .awaitingCamera, .awaitingPose, .countdown, .working:
            break
        }
    }

    private func jumpToFinish() {
        switch routineRunner.phase {
        case .rest:
            routineRunner.skipRest()
        case let .paused(previous):
            routineRunner.resume()
            if case .rest = previous {
                routineRunner.skipRest()
            }
        case .idle, .preparing, .guide, .awaitingCamera, .awaitingPose, .countdown, .working, .complete, .failed:
            break
        }
    }

    private var shouldStartSelectedExerciseFromTimeline: Bool {
        guard model.state.selectedExerciseID != nil else { return false }
        switch routineRunner.phase {
        case .idle, .complete, .failed:
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func startSelectedExercise(mode: CoachExerciseMode, skipsGuide: Bool = false) -> Bool {
        guard let exerciseID = model.state.selectedExerciseID else { return false }
        do {
            try routineRunner.startExercise(exerciseID: exerciseID, mode: mode, target: currentTarget)
            if skipsGuide {
                routineRunner.skipGuide()
            }
            actionError = nil
            return true
        } catch {
            let name = model.state.selectedExerciseName ?? "exercise"
            actionError = "Could not start \(name)."
            return false
        }
    }
}

private struct ExerciseTimeline: View {
    let steps: [TrainingTimelineStep]
    let onSelect: (TrainingTimelineStep) -> Void

    private let connectorWidth: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let connectorCount = max(steps.count - 1, 0)
            let connectorTotalWidth = CGFloat(connectorCount) * connectorWidth
            let nodeCount = max(steps.count, 1)
            let availableNodeWidth = max(0, proxy.size.width - connectorTotalWidth)
            let nodeWidth = max(152, availableNodeWidth / CGFloat(nodeCount))

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { offset, step in
                        TimelineStepButton(step: step, width: nodeWidth, onSelect: onSelect)
                        if offset < steps.count - 1 {
                            TimelineConnector(isComplete: step.state == .complete, width: connectorWidth)
                        }
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: .leading)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
        .frame(height: 108)
    }
}

private struct TimelineStepButton: View {
    let step: TrainingTimelineStep
    let width: CGFloat
    let onSelect: (TrainingTimelineStep) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(step)
        } label: {
            TimelineNode(step: step, width: width, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .help("Jump to \(step.title)")
    }
}

private struct TimelineNode: View {
    let step: TrainingTimelineStep
    let width: CGFloat
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(nodeFill)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: step.state.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(step.state == .upcoming ? step.stage.tint : .white)
                    )
                    .shadow(color: step.state == .current ? step.stage.tint.opacity(0.28) : .clear, radius: 7, y: 2)

                Text(step.stage.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(step.stage.tint)
            }

            Text(step.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(step.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(nodeBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(nodeStroke, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.18), value: isHovered)
    }

    private var nodeFill: Color {
        switch step.state {
        case .complete:
            return .green
        case .current:
            return step.stage.tint
        case .upcoming:
            return step.stage.tint.opacity(0.14)
        }
    }

    private var nodeBackground: Color {
        if step.state == .current {
            return step.stage.tint.opacity(isHovered ? 0.17 : 0.12)
        }
        return isHovered ? step.stage.tint.opacity(0.09) : Color.primary.opacity(0.035)
    }

    private var nodeStroke: Color {
        if step.state == .current {
            return step.stage.tint.opacity(isHovered ? 0.42 : 0.32)
        }
        return isHovered ? step.stage.tint.opacity(0.24) : Color.primary.opacity(0.06)
    }
}

private struct TimelineConnector: View {
    let isComplete: Bool
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(isComplete ? Color.green.opacity(0.62) : Color.secondary.opacity(0.22))
            .frame(width: width - 2, height: 2)
            .padding(.horizontal, 1)
    }
}

private struct TrainingContextPill: View {
    let systemImage: String
    let text: String
    let tint: Color
    var fillOpacity = 0.14
    var strokeOpacity = 0.24

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(fillOpacity), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(strokeOpacity), lineWidth: 1))
    }
}

struct FormTargetOverlay: View {
    let program: ExerciseProgram
    let progress: Double
    let sourceSize: CGSize

    private let timeline: MotionDemoTimeline

    init(program: ExerciseProgram, progress: Double, sourceSize: CGSize) {
        self.program = program
        self.progress = progress
        self.sourceSize = sourceSize
        timeline = MotionDemoBundleStore.timeline(for: program) ?? MotionDemoCompiler.compile(program: program)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let frame = timeline.frame(atElapsedMS: elapsedMilliseconds(from: context.date))
            FormTargetAvatar(frame: frame, progress: progress)
        }
        .animation(.smooth(duration: 0.42), value: progress)
    }

    private func elapsedMilliseconds(from date: Date) -> Int64 {
        let raw = date.timeIntervalSinceReferenceDate * 1000
        return Int64(raw.truncatingRemainder(dividingBy: Double(timeline.durationMS)))
    }
}

private struct FormTargetAvatar: View {
    let frame: PoseFrame
    let progress: Double

    var body: some View {
        ZStack {
            AvatarReferencePoseView(
                frame: frame,
                opacity: 0.38,
                matchProgress: progress
            )

            if progress >= 1 {
                matchedBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
    }

    private var matchedBadge: some View {
        Label("Matched", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.green.opacity(0.18)), in: .capsule)
    }
}
