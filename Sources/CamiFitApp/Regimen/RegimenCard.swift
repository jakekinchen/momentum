import CamiFitEngine
import SwiftUI

struct RegimenCard: View {
    let result: RegimenResult
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @EnvironmentObject private var routineLibrary: RoutineLibraryStore
    @State private var saved = false
    @State private var routineSaveError: String?

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
        let summary = routineSummary(for: routine)

        return card(title: routine.name, subtitle: routine.description ?? "", icon: "sparkles") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 88), spacing: 6),
                    GridItem(.flexible(minimum: 88), spacing: 6)
                ],
                alignment: .leading,
                spacing: 6
            ) {
                RoutineSummaryPill(text: summary.exerciseCountText, systemImage: "figure.strengthtraining.functional")
                RoutineSummaryPill(text: summary.setCountText, systemImage: "repeat")
                RoutineSummaryPill(text: summary.durationText, systemImage: "clock")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(routine.blocks.enumerated()), id: \.offset) { index, block in
                    RoutineExerciseRow(
                        index: index + 1,
                        title: refLabel(block.exerciseRef),
                        target: targetLabel(block),
                        rest: restLabel(block),
                        guidance: block.guidance?.displayText
                    )
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    addRoutine(routine)
                } label: {
                    Label(routineLibrary.contains(routine) ? "Added" : "Add Routine",
                          systemImage: routineLibrary.contains(routine) ? "checkmark" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(routineLibrary.contains(routine))
            }
            .padding(.top, 2)

            if let routineSaveError {
                Text(routineSaveError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if let availabilityText = summary.availabilityText {
                Text(availabilityText)
                    .font(.caption2)
                    .foregroundStyle(.orange)
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

    private func invalidCard(_ kind: RegimenBlockKind, _ message: String) -> some View {
        card(title: "Couldn't read that \(kind == .exercise ? "exercise" : "routine")", subtitle: "Ask the coach to revise.", icon: "exclamationmark.triangle") {
            Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private func refLabel(_ ref: ExerciseRef) -> String {
        switch ref {
        case let .preset(id):
            return humanizedPresetName(id)
        case let .inline(program):
            return program.name
        case let .catalog(_, name):
            return name
        }
    }

    private func targetLabel(_ block: RoutineBlock) -> String {
        if let reps = block.reps {
            return "\(block.sets) \(block.sets == 1 ? "set" : "sets") x \(reps) reps"
        }
        if let holdSeconds = block.holdSeconds {
            return "\(block.sets) \(block.sets == 1 ? "set" : "sets") x \(SetTarget.formatSeconds(holdSeconds))s hold"
        }
        return "\(block.sets) \(block.sets == 1 ? "set" : "sets")"
    }

    private func restLabel(_ block: RoutineBlock) -> String? {
        guard let restSeconds = block.restSeconds, restSeconds > 0 else { return nil }
        return RoutinePresentation.restText(seconds: restSeconds)
    }

    private func routineSummary(for routine: WorkoutRoutine) -> RoutinePresentationSummary {
        let compiler = RoutineCompiler { presetID in
            try model.programForPreset(id: presetID)
        }
        return RoutinePresentation.summary(for: routine, compiler: compiler)
    }

    private func humanizedPresetName(_ id: String) -> String {
        model.availablePresets.first { $0.id == id }?.name ?? id
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    @ViewBuilder
    private func card<C: View>(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct RoutineSummaryPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct RoutineExerciseRow: View {
    let index: Int
    let title: String
    let target: String
    let rest: String?
    let guidance: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.72), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        Text(target)
                        if let rest {
                            Text("·")
                            Text(rest)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(target)
                        if let rest {
                            Text(rest)
                        }
                    }
                }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let guidance {
                    Label(guidance, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
