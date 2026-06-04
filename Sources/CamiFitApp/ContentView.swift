import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppExerciseSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CamiFit")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Exercise", selection: selectedExerciseBinding) {
                    ForEach(viewModel.availablePresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .frame(maxWidth: 260)
            }

            HStack(spacing: 24) {
                stat(label: "Reps", value: "\(viewModel.state.repCount)")
                stat(label: "Hold", value: viewModel.state.holdProgressText)
                stat(label: "Score", value: viewModel.state.scoreText ?? "n/a")
                if let summary = viewModel.lastPoseProviderRunSummary {
                    stat(label: "Frames", value: "\(summary.frameCount)")
                }
                stat(label: "Points", value: "\(viewModel.latestPoseOverlayState.points.count)")
            }

            if let cueText = viewModel.state.cueText {
                Text(cueText)
                    .font(.headline)
            }

            if let diagnosticText = viewModel.lastPoseProviderRunSummary?.diagnosticText ?? viewModel.state.diagnosticText {
                Text(diagnosticText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PoseOverlayView(state: viewModel.latestPoseOverlayState)
                .frame(height: 180)
                .background(.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Picker("Recorded Run", selection: selectedRecordedRunBinding) {
                    ForEach(viewModel.availableRecordedRuns) { run in
                        Text(run.displayName).tag(Optional(run.id))
                    }
                }
                .frame(maxWidth: 260)

                Button("Run") {
                    guard let selectedRecordedRunID = viewModel.selectedRecordedRunID else {
                        return
                    }

                    viewModel.runRecordedRun(id: selectedRecordedRunID)
                }
                .disabled(viewModel.selectedRecordedRunID == nil)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 320)
        .onAppear {
            viewModel.loadAvailablePresets()
            viewModel.loadRecordedRuns()
        }
    }

    private var selectedExerciseBinding: Binding<String?> {
        Binding {
            viewModel.state.selectedExerciseID
        } set: { selectedID in
            guard let selectedID else {
                return
            }

            try? viewModel.selectPreset(id: selectedID)
        }
    }

    private var selectedRecordedRunBinding: Binding<String?> {
        Binding {
            viewModel.selectedRecordedRunID
        } set: { selectedID in
            guard let selectedID else {
                return
            }

            _ = viewModel.runRecordedRun(id: selectedID)
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .monospacedDigit()
        }
    }
}
