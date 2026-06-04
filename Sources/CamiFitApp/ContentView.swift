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
            }

            if let cueText = viewModel.state.cueText {
                Text(cueText)
                    .font(.headline)
            }

            if let diagnosticText = viewModel.state.diagnosticText {
                Text(diagnosticText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 320)
        .onAppear {
            viewModel.loadAvailablePresets()
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
