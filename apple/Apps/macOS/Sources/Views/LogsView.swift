import SwiftUI

struct LogsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.filteredLogs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs", systemImage: "doc.text")
                } description: {
                    if model.logFilter.isEmpty {
                        Text("Log entries will appear here as events occur.")
                    } else {
                        Text("No logs match “\(model.logFilter)”.")
                    }
                }
            } else {
                List(model.filteredLogs, id: \.self) { line in
                    LogEntryRow(text: line)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $model.logFilter, placement: .toolbar, prompt: "Filter logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    withAnimation {
                        model.clearLogs()
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.logs.isEmpty)
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Layout.inlineSpacing) {
            Image(systemName: logIcon)
                .font(.caption2)
                .foregroundStyle(logColor)
                .frame(width: 14, alignment: .center)
                .padding(.top, 3)

            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var logIcon: String {
        let lower = text.lowercased()
        if lower.contains("failed") || lower.contains("error") || lower.contains("could not") {
            return "exclamationmark.circle.fill"
        } else if lower.contains("saved") || lower.contains("exported") || lower.contains("imported") || lower.contains("succeeded") {
            return "checkmark.circle.fill"
        } else if lower.contains("started") || lower.contains("loaded") || lower.contains("reload") {
            return "info.circle.fill"
        }
        return "circle.fill"
    }

    private var logColor: Color {
        let lower = text.lowercased()
        if lower.contains("failed") || lower.contains("error") || lower.contains("could not") {
            return .red
        } else if lower.contains("saved") || lower.contains("exported") || lower.contains("imported") || lower.contains("succeeded") {
            return .green
        } else if lower.contains("started") || lower.contains("loaded") || lower.contains("reload") {
            return .accentColor
        }
        return .secondary
    }
}
