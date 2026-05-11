import Core
import SwiftUI
import UniformTypeIdentifiers

/// Import scrobbles from CSV or JSON files and submit to all active services.
struct FileScrobbleView: View {
    @ObservedObject var model: AppModel
    @State private var importedScrobbles: [ScrobbleData] = []
    @State private var isImporting = false
    @State private var isSubmitting = false
    @State private var parseError: String?
    @State private var submitResult: String?
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    formatHelp

                    if !importedScrobbles.isEmpty {
                        previewSection
                    }

                    if let error = parseError {
                        errorBanner(error)
                    }

                    if let result = submitResult {
                        successBanner(result)
                    }
                }
                .padding(Layout.windowPadding)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !importedScrobbles.isEmpty {
                Divider()
                actionFooter
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose File…", systemImage: "doc.badge.plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private var subtitle: String {
        importedScrobbles.isEmpty ? "" : "\(importedScrobbles.count) loaded"
    }

    // MARK: - Format Help

    private var formatHelp: some View {
        GroupBox("Supported Formats") {
            VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                formatRow("CSV", icon: "tablecells", description: "artist, track, album, timestamp")
                Divider()
                formatRow("JSON", icon: "curlybraces", description: "[{ artist, track, album, timestamp }]")
            }
            .padding(.vertical, 4)
        }
    }

    private func formatRow(_ title: String, icon: String, description: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Preview

    private var previewSection: some View {
        GroupBox("Preview") {
            VStack(spacing: 0) {
                ForEach(Array(importedScrobbles.prefix(50).enumerated()), id: \.offset) { index, data in
                    HStack(spacing: Layout.sectionSpacing) {
                        Text("\(index + 1)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.track)
                                .font(.callout)
                                .lineLimit(1)
                            Text(data.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let album = data.album, !album.isEmpty {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .frame(maxWidth: 200, alignment: .trailing)
                        }

                        Text(data.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    if index < min(importedScrobbles.count, 50) - 1 {
                        Divider()
                    }
                }

                if importedScrobbles.count > 50 {
                    Divider()
                    Text("… and \(importedScrobbles.count - 50) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.inlineSpacing)
                }
            }
        }
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
    }

    private func successBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.callout)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        HStack(spacing: Layout.inlineSpacing) {
            Button {
                importedScrobbles = []
                parseError = nil
                submitResult = nil
            } label: {
                Label("Clear", systemImage: "xmark")
            }

            Spacer()

            Button {
                Task { await submitAll() }
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Submit All", systemImage: "paperplane.fill")
                }
            }
            .prominentGlassButton()
            .disabled(isSubmitting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Layout.windowPadding)
    }

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        parseError = nil
        submitResult = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                parseError = "Cannot access file — permission denied."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let ext = url.pathExtension.lowercased()

                if ext == "json" {
                    importedScrobbles = try parseJSON(content)
                } else {
                    importedScrobbles = try parseCSV(content)
                }
            } catch {
                parseError = "Failed to parse file: \(error.localizedDescription)"
            }

        case .failure(let error):
            parseError = "File picker error: \(error.localizedDescription)"
        }
    }

    private func parseCSV(_ content: String) throws -> [ScrobbleData] {
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { throw FileParseError.empty }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count >= 2 else { return nil }
            let artist = fields[0].trimmingCharacters(in: .whitespaces)
            let track = fields[1].trimmingCharacters(in: .whitespaces)
            let album = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespaces) : nil
            let timestamp: Date
            if fields.count > 3, let ts = parseTimestamp(fields[3].trimmingCharacters(in: .whitespaces)) {
                timestamp = ts
            } else {
                timestamp = Date()
            }
            return ScrobbleData(artist: artist, track: track, album: album, timestamp: timestamp)
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private func parseJSON(_ content: String) throws -> [ScrobbleData] {
        guard let data = content.data(using: .utf8) else { throw FileParseError.invalidJSON }
        let entries = try JSONDecoder().decode([FileScrobbleEntry].self, from: data)
        return entries.map { entry in
            ScrobbleData(
                artist: entry.artist,
                track: entry.track,
                album: entry.album,
                timestamp: parseTimestamp(entry.timestamp ?? "") ?? Date()
            )
        }
    }

    private func parseTimestamp(_ string: String) -> Date? {
        if let unix = TimeInterval(string) { return Date(timeIntervalSince1970: unix) }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        let dateFormatter = DateFormatter()
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "dd/MM/yyyy HH:mm"] {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: string) { return date }
        }
        return nil
    }

    // MARK: - Submit

    private func submitAll() async {
        isSubmitting = true
        submitResult = nil

        var succeeded = 0
        for data in importedScrobbles {
            await model.manualScrobble(data)
            succeeded += 1
        }

        withAnimation(.spring(duration: 0.3)) {
            submitResult = "Submitted \(succeeded) scrobble(s) to \(model.accounts.filter(\.enabled).count) service(s)."
        }
        isSubmitting = false
    }
}

// MARK: - Helper Types

private struct FileScrobbleEntry: Codable {
    let artist: String
    let track: String
    let album: String?
    let timestamp: String?
}

private enum FileParseError: LocalizedError {
    case empty
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .empty: "File is empty or has no data rows."
        case .invalidJSON: "Could not parse JSON content."
        }
    }
}
