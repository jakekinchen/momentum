import SwiftUI

struct AssignmentCopilotFactCardView: View {
    let card: AssignmentCopilotFactCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: card.hasSupportingFact ? "chart.line.uptrend.xyaxis" : "questionmark.diamond")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(card.hasSupportingFact ? .indigo : .orange)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.caption.weight(.semibold))
                    Text(card.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !card.chart.isEmpty {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(card.chart.prefix(10)) { point in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.indigo.opacity(0.45))
                            .frame(width: 8, height: max(4, min(44, point.value * 4)))
                            .help("\(point.label): \(point.value)")
                    }
                }
                .frame(height: 48, alignment: .bottomLeading)
            }

            if !card.evidenceNodeIDs.isEmpty {
                Text(card.evidenceNodeIDs.prefix(2).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill((card.hasSupportingFact ? Color.indigo : Color.orange).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke((card.hasSupportingFact ? Color.indigo : Color.orange).opacity(0.16), lineWidth: 1)
                )
        )
        .frame(maxWidth: 280, alignment: .leading)
    }
}
