import CamiFitEngine
import SwiftUI

struct RegimenCard: View {
    let result: RegimenResult
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @State private var saved = false

    var body: some View {
        switch result {
        case let .exercise(program): exerciseCard(program)
        case let .routine(routine): routineCard(routine)
        case let .invalid(kind, message): invalidCard(kind, message)
        }
    }

    private func exerciseCard(_ program: ExerciseProgram) -> some View {
        card(title: program.name, subtitle: program.hold == nil ? "Counts reps" : "Timed hold", icon: "figure.strengthtraining.functional") {
            Text("Generated — may need tuning").font(.caption2).foregroundStyle(.orange)
            HStack {
                Button(saved ? "Added" : "Save & add to exercises") {
                    do { try model.saveGeneratedExercise(program); saved = true } catch { saved = false }
                }.buttonStyle(.borderedProminent).disabled(saved)
            }
        }
    }

    private func routineCard(_ routine: WorkoutRoutine) -> some View {
        card(title: routine.name, subtitle: routine.description ?? "", icon: "list.bullet.rectangle") {
            ForEach(Array(routine.blocks.enumerated()), id: \.offset) { _, block in
                Text("• \(refLabel(block.exerciseRef)) — \(block.sets)×\(block.reps.map(String.init) ?? block.holdSeconds.map { "\(Int($0))s" } ?? "?")")
                    .font(.caption)
            }
            Button("Start routine") { try? model.startRoutine(routine) }.buttonStyle(.bordered)
        }
    }

    private func invalidCard(_ kind: RegimenBlockKind, _ message: String) -> some View {
        card(title: "Couldn't read that \(kind == .exercise ? "exercise" : "routine")", subtitle: "Ask the coach to revise.", icon: "exclamationmark.triangle") {
            Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private func refLabel(_ ref: ExerciseRef) -> String {
        switch ref { case let .preset(id): return id; case let .inline(p): return p.name }
    }

    @ViewBuilder
    private func card<C: View>(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
