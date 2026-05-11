import Core
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selectedTrack: LastFMTrack?
    @State private var selectedAlbum: LastFMAlbum?
    @State private var selectedArtist: LastFMArtist?

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search Last.fm",
                    systemImage: "magnifyingglass",
                    description: Text("Type to search Last.fm artists, albums, and tracks.")
                )
            } else if !model.isSearching
                && model.searchArtists.isEmpty
                && model.searchAlbums.isEmpty
                && model.searchTracks.isEmpty
            {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No matches found for “\(query)”.")
                )
            } else {
                resultsList
            }
        }
        .navigationSubtitle(model.isSearching ? "Searching…" : "")
        .searchable(text: $query, placement: .toolbar, prompt: "Artists, albums, tracks")
        .onChange(of: query) { _, newValue in
            model.performSearch(query: newValue)
        }
        .onSubmit(of: .search) {
            model.performSearch(query: query)
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

    private var resultsList: some View {
        List {
            if !model.searchArtists.isEmpty {
                Section("Artists") {
                    ForEach(model.searchArtists) { artist in
                        Button {
                            selectedArtist = artist
                        } label: {
                            SearchArtistRow(artist: artist)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.searchAlbums.isEmpty {
                Section("Albums") {
                    ForEach(model.searchAlbums) { album in
                        Button {
                            selectedAlbum = album
                        } label: {
                            SearchAlbumRow(album: album)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.searchTracks.isEmpty {
                Section("Tracks") {
                    ForEach(model.searchTracks) { track in
                        Button {
                            selectedTrack = track
                        } label: {
                            SearchTrackRow(track: track)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Search Result Rows

private struct SearchArtistRow: View {
    var artist: LastFMArtist

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: .artist(name: artist.name),
                hint: artist.imageURL,
                placeholderSymbol: "person.fill"
            )
            .frame(width: 32, height: 32)

            Text(artist.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let plays = artist.playcount?.intValue, plays > 0 {
                Text("\(plays.formatted()) plays")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SearchAlbumRow: View {
    var album: LastFMAlbum

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: .album(artist: album.artist?.name ?? "", name: album.name),
                hint: album.imageURL,
                placeholderSymbol: "opticaldisc.fill"
            )
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)

                if let artistName = album.artist?.name {
                    Text(artistName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let plays = album.playcount?.intValue, plays > 0 {
                Text("\(plays.formatted())")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SearchTrackRow: View {
    var track: LastFMTrack

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: .track(artist: track.artist.name, title: track.name),
                hint: track.imageURL,
                placeholderSymbol: "music.note"
            )
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.body)
                    .lineLimit(1)

                Text(track.artist.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let plays = track.playcount?.intValue, plays > 0 {
                Text("\(plays.formatted())")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
