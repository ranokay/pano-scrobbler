import SwiftUI

struct LogsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)

            Divider()

            logList
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13))

            TextField("Filter logs…", text: $model.logFilter)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if !model.logs.isEmpty {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        model.clearLogs()
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 12))
                }

            }
        }
    }

    // MARK: - Log List

    private var logList: some View {
        Group {
            if model.filteredLogs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs", systemImage: "doc.text")
                } description: {
                    if model.logFilter.isEmpty {
                        Text("Log entries will appear here as events occur.")
                    } else {
                        Text("No logs match \"\(model.logFilter)\".")
                    }
                }
            } else {
                List(model.filteredLogs, id: \.self) { line in
                    LogEntryRow(text: line)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: logIcon)
                .font(.system(size: 9))
                .foregroundStyle(logColor)
                .frame(width: 14, alignment: .center)
                .padding(.top, 3)

            Text(text)
                .font(.logEntry)
                .foregroundStyle(.primary)
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
            return AccentColors.error
        } else if lower.contains("saved") || lower.contains("exported") || lower.contains("imported") || lower.contains("succeeded") {
            return AccentColors.success
        } else if lower.contains("started") || lower.contains("loaded") || lower.contains("reload") {
            return AccentColors.primary
        }
        return .secondary
    }
}
