import SwiftUI
import Core
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                importSection
                if !importedScrobbles.isEmpty { previewSection }
                if let error = parseError { errorSection(error) }
                if let result = submitResult { resultSection(result) }
            }
            .padding(Spacing.lg)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Scrobble from File")
                .font(.displayLarge)
            Text("Import scrobbles from a CSV or JSON file and submit them to all active services.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Import

    private var importSection: some View {
        GlassCard(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Supported Formats")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: Spacing.lg) {
                    formatInfo("CSV", icon: "tablecells", description: "artist, track, album, timestamp")
                    formatInfo("JSON", icon: "curlybraces", description: "[{artist, track, album, timestamp}]")
                }

                Divider()

                HStack(spacing: Spacing.md) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose File…", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    if !importedScrobbles.isEmpty {
                        Text("\(importedScrobbles.count) scrobble(s) loaded")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
    }

    private func formatInfo(_ title: String, icon: String, description: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Preview (\(importedScrobbles.count) entries)")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    Task { await submitAll() }
                } label: {
                    Label(isSubmitting ? "Submitting…" : "Submit All", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                Button {
                    importedScrobbles = []
                    parseError = nil
                    submitResult = nil
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }

            GlassCard(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(importedScrobbles.prefix(50).enumerated()), id: \.offset) { index, data in
                        HStack(spacing: Spacing.md) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(data.track)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(data.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let album = data.album, !album.isEmpty {
                                Text(album)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 200, alignment: .trailing)
                            }

                            Text(data.timestamp, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, Spacing.sm)

                        if index < min(importedScrobbles.count, 50) - 1 {
                            Divider()
                        }
                    }

                    if importedScrobbles.count > 50 {
                        Text("… and \(importedScrobbles.count - 50) more")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(Spacing.sm)
                    }
                }
            }
        }
    }

    // MARK: - Status Sections

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AccentColors.error)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AccentColors.error)
        }
    }

    private func resultSection(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AccentColors.success)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AccentColors.success)
        }
        .transition(.scale.combined(with: .opacity))
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
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { throw FileParseError.empty }

        // Skip header row
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
            submitResult = "Successfully submitted \(succeeded) scrobble(s) to \(model.accounts.filter(\.enabled).count) service(s)."
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
