import SwiftUI
import Core

struct SearchView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selectedTrack: LastFMTrack?
    @State private var selectedAlbum: LastFMAlbum?
    @State private var selectedArtist: LastFMArtist?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                searchBar
                searchResults
            }
            .padding(Spacing.lg)
        }
        .sheet(item: $selectedTrack) { track in
            MusicEntryInfoView(model: model, track: track, album: nil, artist: nil)
        }
        .sheet(item: $selectedAlbum) { album in
            MusicEntryInfoView(model: model, track: nil, album: album, artist: nil)
        }
        .sheet(item: $selectedArtist) { artist in
            MusicEntryInfoView(model: model, track: nil, album: nil, artist: artist)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Search")
                .font(.displayLarge)

            Text("Search your Last.fm library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Artists, albums, tracks…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit {
                    model.performSearch(query: query)
                }
                .onChange(of: query) { _, newValue in
                    model.performSearch(query: newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    model.performSearch(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Results

    @ViewBuilder
    private var searchResults: some View {
        if query.isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Type to search across your Last.fm artists, albums, and tracks.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else if !model.isSearching && model.searchArtists.isEmpty && model.searchAlbums.isEmpty && model.searchTracks.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No matches found for \"\(query)\".")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if !model.searchArtists.isEmpty {
                    resultSection("Artists", icon: "person.fill") {
                        ForEach(model.searchArtists) { artist in
                            SearchArtistRow(artist: artist)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedArtist = artist }
                        }
                    }
                }

                if !model.searchAlbums.isEmpty {
                    resultSection("Albums", icon: "opticaldisc.fill") {
                        ForEach(model.searchAlbums) { album in
                            SearchAlbumRow(album: album)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedAlbum = album }
                        }
                    }
                }

                if !model.searchTracks.isEmpty {
                    resultSection("Tracks", icon: "music.note") {
                        ForEach(model.searchTracks) { track in
                            SearchTrackRow(track: track)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTrack = track }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }

            LazyVStack(spacing: Spacing.xs) {
                content()
            }
        }
    }
}

// MARK: - Search Result Rows

private struct SearchArtistRow: View {
    var artist: LastFMArtist

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                Text(artist.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if let plays = artist.playcount?.intValue, plays > 0 {
                    Text("\(plays) plays")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SearchAlbumRow: View {
    var album: LastFMAlbum

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                if let url = album.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            albumPlaceholder
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    albumPlaceholder
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let artistName = album.artist?.name {
                        Text(artistName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let plays = album.playcount?.intValue, plays > 0 {
                    Text("\(plays) plays")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
    }
}

private struct SearchTrackRow: View {
    var track: LastFMTrack

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(track.artist.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let plays = track.playcount?.intValue, plays > 0 {
                    Text("\(plays) plays")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
