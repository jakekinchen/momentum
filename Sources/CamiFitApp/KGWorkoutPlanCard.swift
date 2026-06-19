import SwiftUI

struct KGWorkoutPlanCard: View {
    let artifact: KGWorkoutChatArtifact
    let onShowMemory: (String?) -> Void
    @State private var showsTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: artifact.memoryReferences.isEmpty ? "checkmark.shield" : "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(artifact.memoryReferences.isEmpty ? .green : .pink)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalized decision")
                        .font(.caption.weight(.semibold))
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    showsTechnicalDetails.toggle()
                } label: {
                    Image(systemName: showsTechnicalDetails ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(showsTechnicalDetails ? "Hide decision details" : "Show decision details")
            }

            Button {
                onShowMemory(artifact.memoryReferences.first?.operationID)
            } label: {
                Label(memoryButtonTitle, systemImage: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(artifact.memoryReferences.isEmpty)
            .help(artifact.memoryReferences.isEmpty
                  ? "No saved memory was used for this plan"
                  : "Open the memory used for this plan")

            if showsTechnicalDetails {
                Divider().opacity(0.4)

                evidenceSection("Selected", rows: Array(artifact.selected.prefix(3)))
                evidenceSection("Recommend only", rows: Array(artifact.recommendOnlySelected.prefix(4)))
                evidenceSection("Filtered", rows: Array(artifact.filtered.prefix(3)))

                if !artifact.presetMappings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Runnable mappings")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(artifact.presetMappings.prefix(4)) { mapping in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(mapping.kgExerciseName) -> \(mapping.presetID)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(mapping.readinessStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.teal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.teal.opacity(0.16), lineWidth: 1)
                )
        )
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var summaryText: String {
        if !artifact.recommendOnlySelected.isEmpty {
            return "\(artifact.recommendOnlySelected.count) selected KG exercise(s) are recommendation-only for tracking."
        }
        if artifact.memoryReferences.isEmpty {
            return "This plan used your equipment and safety rules."
        }
        if artifact.memoryReferences.count == 1 {
            return "This plan used a saved memory."
        }
        return "This plan used saved memories."
    }

    private var memoryButtonTitle: String {
        artifact.memoryReferences.isEmpty ? "No saved memory used" : "See why"
    }

    private func evidenceSection(_ title: String, rows: [KGWorkoutDecisionEvidence]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("None")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(2)
                        Text(row.primaryReasonCode)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
