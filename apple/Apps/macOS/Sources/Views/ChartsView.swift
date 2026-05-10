import SwiftUI
import Core
import Services

struct ChartsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTrack: LastFMTrack?
    @State private var selectedAlbum: LastFMAlbum?
    @State private var selectedArtist: LastFMArtist?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                periodPicker
                chartsContent
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            if model.chartArtists.isEmpty {
                model.loadCharts()
            }
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
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Charts")
                    .font(.displayLarge)
                Text("Your top artists, albums, and tracks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.loadCharts()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingCharts)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Time Period", selection: Binding(
            get: { model.chartPeriod },
            set: { model.loadCharts(period: $0) }
        )) {
            ForEach(LastFMPeriod.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Content

    @ViewBuilder
    private var chartsContent: some View {
        if model.isLoadingCharts && model.chartArtists.isEmpty {
            ProgressView("Loading charts…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
        } else if model.chartArtists.isEmpty && model.chartAlbums.isEmpty && model.chartTracks.isEmpty {
            ContentUnavailableView(
                "No Charts",
                systemImage: "chart.bar.fill",
                description: Text("Listen to some music and check back later.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                chartSection("Top Artists", items: model.chartArtists) { artist in
                    ChartArtistRow(artist: artist, rank: model.chartArtists.firstIndex(where: { $0.name == artist.name }).map { $0 + 1 } ?? 0)
                }

                chartSection("Top Albums", items: model.chartAlbums) { album in
                    ChartAlbumRow(album: album, rank: model.chartAlbums.firstIndex(where: { $0.id == album.id }).map { $0 + 1 } ?? 0)
                }

                chartSection("Top Tracks", items: model.chartTracks) { track in
                    ChartTrackRow(track: track, rank: model.chartTracks.firstIndex(where: { $0.id == track.id }).map { $0 + 1 } ?? 0)
                }
            }
        }
    }

    @ViewBuilder
    private func chartSection<T: Identifiable, Content: View>(
        _ title: String,
        items: [T],
        @ViewBuilder row: @escaping (T) -> Content
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(.headline)

                LazyVStack(spacing: Spacing.xs) {
                    ForEach(items) { item in
                        row(item)
                            .contentShape(Rectangle())
                            .onTapGesture { onItemTap(item) }
                    }
                }
            }
        }
    }

    private func onItemTap<T>(_ item: T) {
        if let artist = item as? LastFMArtist {
            selectedArtist = artist
        } else if let album = item as? LastFMAlbum {
            selectedAlbum = album
        } else if let track = item as? LastFMTrack {
            selectedTrack = track
        }
    }
}

// MARK: - Chart Rows

private struct ChartArtistRow: View {
    var artist: LastFMArtist
    var rank: Int

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                RankBadge(rank: rank)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let plays = artist.playcount?.intValue, plays > 0 {
                        Text("\(plays) plays")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
    }
}

private struct ChartAlbumRow: View {
    var album: LastFMAlbum
    var rank: Int

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                RankBadge(rank: rank)

                if let url = album.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            albumPlaceholder
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    albumPlaceholder
                        .frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let artistName = album.artist?.name {
                        Text(artistName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let plays = album.playcount?.intValue, plays > 0 {
                        Text("\(plays) plays")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
    }
}

private struct ChartTrackRow: View {
    var track: LastFMTrack
    var rank: Int

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                RankBadge(rank: rank)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(track.artist.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let plays = track.playcount?.intValue, plays > 0 {
                        Text("\(plays) plays")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }
}

private struct RankBadge: View {
    var rank: Int

    var body: some View {
        Text("#\(rank)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(rankColor)
            .frame(width: 32, alignment: .center)
    }

    private var rankColor: Color {
        switch rank {
        case 1: .yellow
        case 2: Color(hue: 0, saturation: 0, brightness: 0.75)
        case 3: Color(hue: 0.07, saturation: 0.6, brightness: 0.75)
        default: .secondary
        }
    }
}
