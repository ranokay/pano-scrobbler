import SwiftUI
import Core
import Services

/// Search and preview album artwork from iTunes and Deezer.
struct ImageSearchView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var results: [ArtworkResult] = []
    @State private var isSearching = false
    @State private var selectedResult: ArtworkResult?
    @State private var searchTask: Task<Void, Never>?

    private let service = ArtworkLookupService()
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: Spacing.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                searchBar
                resultsGrid
            }
            .padding(Spacing.lg)
        }
        .sheet(item: $selectedResult) { result in
            artworkDetailSheet(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Artwork Search")
                .font(.displayLarge)
            Text("Find album and artist artwork from iTunes and Deezer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search artist, album, or track…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(Spacing.sm)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            Button("Search") {
                performSearch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
    }

    // MARK: - Results Grid

    @ViewBuilder
    private var resultsGrid: some View {
        if results.isEmpty && !isSearching {
            VStack(spacing: Spacing.md) {
                Spacer(minLength: 60)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("Search for artwork to get started")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(results) { result in
                    artworkCard(result)
                }
            }
        }
    }

    private func artworkCard(_ result: ArtworkResult) -> some View {
        VStack(spacing: Spacing.xs) {
            // Thumbnail
            AsyncImage(url: result.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                case .empty:
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { ProgressView().scaleEffect(0.6) }
                @unknown default:
                    Rectangle().fill(.quaternary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(result.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(result.source.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { selectedResult = result }
        .contentShape(Rectangle())
    }

    // MARK: - Detail Sheet

    private func artworkDetailSheet(_ result: ArtworkResult) -> some View {
        VStack(spacing: Spacing.lg) {
            Text(result.title)
                .font(.title2.weight(.semibold))

            Text(result.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AsyncImage(url: result.imageURL ?? result.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    Rectangle()
                        .fill(.quaternary)
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
            .frame(maxWidth: 400, maxHeight: 400)

            HStack(spacing: Spacing.md) {
                if let url = result.imageURL ?? result.thumbnailURL {
                    Button {
                        saveArtwork(url: url, name: "\(result.artist) - \(result.title)")
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Button("Close") {
                    selectedResult = nil
                }
                .buttonStyle(.bordered)
            }

            Text("Source: \(result.source.rawValue)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.xl)
        .frame(minWidth: 450, minHeight: 500)
    }

    // MARK: - Actions

    private func performSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

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

                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try pngData.write(to: saveURL)
                }
            } catch {
                // silently fail
            }
        }
    }
}
