import SwiftUI

struct KGMemoryPanel: View {
    @ObservedObject var store: KGMemoryStore
    var focusedOperationID: String?
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
                Text(KGMemoryDisplay.headerSubtitle)
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
            let activeItems = store.state.items.filter { $0.category == .healthSafety && $0.status == .active }
            if activeItems.isEmpty {
                panelMessage("No active health or safety memories")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let correctionError {
                                Text(correctionError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                            }
                            memorySection(
                                title: "Health & Safety",
                                items: activeItems
                            )
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        scrollToFocusedMemory(with: proxy)
                    }
                    .onChange(of: focusedOperationID) { _, _ in
                        scrollToFocusedMemory(with: proxy)
                    }
                }
            }
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
                        KGMemoryRow(
                            item: item,
                            isFocused: item.operationID == focusedOperationID
                        ) {
                            delete(item)
                        }
                        .id(item.operationID)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func scrollToFocusedMemory(with proxy: ScrollViewProxy) {
        guard let focusedOperationID else { return }
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                proxy.scrollTo(focusedOperationID, anchor: .top)
            }
        }
    }

    private func delete(_ item: KGMemoryItem) {
        do {
            try store.correctHealthMemory(
                operationID: item.operationID,
                reason: KGMemoryDisplay.deleteReason
            )
            correctionError = nil
        } catch {
            correctionError = String(describing: error)
        }
    }
}

private struct KGMemoryRow: View {
    let item: KGMemoryItem
    let isFocused: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer(minLength: 0)

                if item.status == .active {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete memory")
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Source message")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("“\(item.sourceText)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                metadata("Remembered", KGMemoryDisplay.formattedDate(item.createdAt))
                if let reason = item.reason {
                    metadata("Reason", reason)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.075), lineWidth: 1)
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
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum KGMemoryDisplay {
    static let headerSubtitle = "Control what your coach remembers about you"
    static let deleteReason = "Deleted from Memories panel."

    static func formattedDate(_ rawValue: String,
                              locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        guard let date = iso8601Date(from: rawValue) else {
            return rawValue
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func iso8601Date(from rawValue: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) {
            return date
        }
        return ISO8601DateFormatter().date(from: rawValue)
    }
}
