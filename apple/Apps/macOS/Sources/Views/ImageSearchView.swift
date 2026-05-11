import AppKit
import Core
import Services
import SwiftUI

/// Search and preview album artwork from iTunes and Deezer.
struct ImageSearchView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var results: [ArtworkResult] = []
    @State private var isSearching = false
    @State private var selectedResult: ArtworkResult?
    @State private var searchTask: Task<Void, Never>?

    private let service = ArtworkLookupService()
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: Layout.sectionSpacing)]

    var body: some View {
        ScrollView {
            if results.isEmpty && !isSearching {
                ContentUnavailableView(
                    "Find Artwork",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Search for artist, album, or track artwork.")
                )
                .padding(.vertical, 80)
            } else {
                LazyVGrid(columns: columns, spacing: Layout.sectionSpacing) {
                    ForEach(results) { result in
                        artworkCard(result)
                    }
                }
                .padding(Layout.windowPadding)
            }
        }
        .navigationSubtitle(isSearching ? "Searching…" : "")
        .searchable(text: $query, placement: .toolbar, prompt: "Artist, album, or track")
        .onSubmit(of: .search) { performSearch() }
        .toolbar {
            if isSearching {
                ToolbarItem(placement: .status) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .sheet(item: $selectedResult) { result in
            artworkDetailSheet(result)
        }
    }

    // MARK: - Card

    private func artworkCard(_ result: ArtworkResult) -> some View {
        VStack(spacing: Layout.inlineSpacing) {
            AsyncImage(url: result.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(.background.tertiary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                case .empty:
                    Rectangle()
                        .fill(.background.tertiary)
                        .overlay { ProgressView().controlSize(.small) }
                @unknown default:
                    Rectangle().fill(.background.tertiary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(result.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(result.source.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.inlineSpacing)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .onTapGesture { selectedResult = result }
        .contentShape(Rectangle())
        .contextMenu {
            if let url = result.imageURL ?? result.thumbnailURL {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }

                Button {
                    saveArtwork(url: url, name: "\(result.artist) - \(result.title)")
                } label: {
                    Label("Save Image…", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    // MARK: - Detail Sheet

    private func artworkDetailSheet(_ result: ArtworkResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(result.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    selectedResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding(Layout.windowPadding)

            Divider()

            ScrollView {
                AsyncImage(url: result.imageURL ?? result.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.background.tertiary)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.tertiary)
                            }
                    case .empty:
                        ProgressView()
                            .frame(width: 300, height: 300)
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(Layout.windowPadding)
            }
            .frame(maxHeight: 460)

            Divider()

            HStack(spacing: Layout.inlineSpacing) {
                Text("Source: \(result.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let url = result.imageURL ?? result.thumbnailURL {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }

                    Button {
                        saveArtwork(url: url, name: "\(result.artist) - \(result.title)")
                    } label: {
                        Label("Save Image…", systemImage: "square.and.arrow.down")
                    }
                    .prominentGlassButton()
                }
            }
            .padding(Layout.windowPadding)
        }
        .frame(minWidth: 480, minHeight: 540)
    }

    // MARK: - Actions

    private func performSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }

        isSearching = true
        searchTask = Task {
            let found = await service.search(query: q, limit: 15)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func saveArtwork(url: URL, name: String) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else { return }

                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.nameFieldStringValue = "\(name).png"
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let saveURL = panel.url else { return }

                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData) else {
                    showSaveError("Could not decode the image for saving.")
                    return
                }

                let isJPEG = ["jpg", "jpeg"].contains(saveURL.pathExtension.lowercased())
                let fileType: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
                let properties: [NSBitmapImageRep.PropertyKey: Any] = isJPEG ? [.compressionFactor: 0.9] : [:]

                guard let imageData = bitmap.representation(using: fileType, properties: properties) else {
                    showSaveError("Could not encode the selected image.")
                    return
                }

                try imageData.write(to: saveURL)
            } catch {
                showSaveError(error.localizedDescription)
            }
        }
    }

    private func showSaveError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
