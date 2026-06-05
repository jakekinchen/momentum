import SwiftUI

struct KGMemoryPanel: View {
    @ObservedObject var store: KGMemoryStore
    @State private var correctionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.45)

            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.58),
                        Color(nsColor: .windowBackgroundColor).opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .onAppear {
            if store.state.phase == .idle {
                store.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.pink.opacity(0.18))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.pink)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Memories")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Revision \(store.state.overlayRevision) · Base \(store.state.baseArtifactShortHash)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state.phase {
        case .idle, .loading:
            panelMessage("Loading memories")
        case .empty:
            panelMessage("No health or safety memories")
        case .error:
            panelMessage(store.state.errorMessage ?? "Memory load failed")
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let correctionError {
                        Text(correctionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                    memorySection(
                        title: "Active Health & Safety",
                        items: store.state.items.filter { $0.category == .healthSafety && $0.status == .active }
                    )
                    memorySection(
                        title: "Archived / Corrected",
                        items: store.state.items.filter { $0.category == .healthSafety && $0.status == .corrected }
                    )
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private func panelMessage(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func memorySection(title: String, items: [KGMemoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            if items.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        KGMemoryRow(item: item) {
                            correct(item)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func correct(_ item: KGMemoryItem) {
        do {
            try store.correctHealthMemory(
                operationID: item.operationID,
                reason: "Marked resolved from Memories panel."
            )
            correctionError = nil
        } catch {
            correctionError = String(describing: error)
        }
    }
}

private struct KGMemoryRow: View {
    let item: KGMemoryItem
    let onCorrect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer(minLength: 0)
            }

            Text(item.sourceText)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                metadata("Operation", item.operationID)
                metadata("Actor", item.actor.rawValue)
                metadata("Date", item.createdAt)
                if let reason = item.reason {
                    metadata("Reason", reason)
                }
                if !item.evidence.isEmpty {
                    metadata("Evidence", item.evidence.joined(separator: ", "))
                }
            }

            if item.status == .active {
                Button {
                    onCorrect()
                } label: {
                    Label("Mark Resolved", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.075), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        switch item.status {
        case .active: return "Active"
        case .corrected: return "Corrected"
        case .archived: return "Archived"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .active: return .orange
        case .corrected: return .green
        case .archived: return .secondary
        }
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
