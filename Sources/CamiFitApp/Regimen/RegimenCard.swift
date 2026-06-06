import CamiFitEngine
import SwiftUI

struct RegimenCard: View {
    let result: RegimenResult
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineRunner: RoutineRunner
    @EnvironmentObject private var routineLibrary: RoutineLibraryStore
    @State private var saved = false
    @State private var routineSaveError: String?
    @State private var previewsRoutine = false

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
        card(title: routine.name, subtitle: routine.description ?? "", icon: "sparkles") {
            if previewsRoutine {
                ForEach(Array(routine.blocks.enumerated()), id: \.offset) { index, block in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text("\(refLabel(block.exerciseRef)) - \(targetLabel(block))")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        previewsRoutine.toggle()
                    } label: {
                        Label(previewsRoutine ? "Hide" : "Preview", systemImage: previewsRoutine ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        startRoutine(routine)
                    } label: {
                        Label("Start Now", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    addRoutine(routine)
                } label: {
                    Label(routineLibrary.contains(routine) ? "Added" : "Add to Library",
                          systemImage: routineLibrary.contains(routine) ? "checkmark" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(routineLibrary.contains(routine))
            }

            if let routineSaveError {
                Text(routineSaveError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func addRoutine(_ routine: WorkoutRoutine) {
        do {
            try routineLibrary.add(routine)
            routineSaveError = nil
        } catch {
            routineSaveError = String(describing: error)
        }
    }

    private func startRoutine(_ routine: WorkoutRoutine) {
        do {
            try routineRunner.start(routine)
            routineSaveError = nil
        } catch {
            routineSaveError = String(describing: error)
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

    private func targetLabel(_ block: RoutineBlock) -> String {
        if let reps = block.reps {
            return "\(block.sets)x\(reps) reps"
        }
        if let holdSeconds = block.holdSeconds {
            return "\(block.sets)x\(Int(holdSeconds))s hold"
        }
        return "\(block.sets) sets"
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
