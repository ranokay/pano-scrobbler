import Core
import Services
import SwiftUI

struct ChartsView: View {
    @ObservedObject var model: AppModel
    @State private var chartType: ChartType = .artists
    @State private var selectedTrack: LastFMTrack?
    @State private var selectedAlbum: LastFMAlbum?
    @State private var selectedArtist: LastFMArtist?

    enum ChartType: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case albums = "Albums"
        case tracks = "Tracks"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar

            Divider()

            chartsContent
        }
        .navigationSubtitle(model.chartPeriod.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.loadCharts()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingCharts)
            }
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

    // MARK: - Controls

    private var controlsBar: some View {
        VStack(spacing: Layout.inlineSpacing) {
            Picker("Type", selection: $chartType) {
                ForEach(ChartType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Period", selection: Binding(
                get: { model.chartPeriod },
                set: { model.loadCharts(period: $0) }
            )) {
                ForEach(LastFMPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, Layout.windowPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var chartsContent: some View {
        if model.isLoadingCharts && model.chartArtists.isEmpty && model.chartAlbums.isEmpty && model.chartTracks.isEmpty {
            ProgressView("Loading charts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentItemsIsEmpty {
            ContentUnavailableView(
                "No Charts",
                systemImage: "chart.bar.fill",
                description: Text("Listen to some music and check back later.")
            )
        } else {
            List {
                switch chartType {
                case .artists:
                    ForEach(Array(model.chartArtists.enumerated()), id: \.element.id) { index, artist in
                        ChartArtistRow(artist: artist, rank: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedArtist = artist }
                    }

                case .albums:
                    ForEach(Array(model.chartAlbums.enumerated()), id: \.element.id) { index, album in
                        ChartAlbumRow(album: album, rank: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAlbum = album }
                    }

                case .tracks:
                    ForEach(Array(model.chartTracks.enumerated()), id: \.element.id) { index, track in
                        ChartTrackRow(track: track, rank: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTrack = track }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var currentItemsIsEmpty: Bool {
        switch chartType {
        case .artists: return model.chartArtists.isEmpty
        case .albums: return model.chartAlbums.isEmpty
        case .tracks: return model.chartTracks.isEmpty
        }
    }
}

// MARK: - Chart Rows

private struct ChartArtistRow: View {
    var artist: LastFMArtist
    var rank: Int

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            RankBadge(rank: rank)

            AsyncArtwork(
                subject: .artist(name: artist.name),
                hint: artist.imageURL,
                placeholderSymbol: "person.fill"
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)

                if let plays = artist.playcount?.intValue, plays > 0 {
                    Text("\(plays.formatted()) plays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct ChartAlbumRow: View {
    var album: LastFMAlbum
    var rank: Int

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            RankBadge(rank: rank)

            AsyncArtwork(
                subject: .album(artist: album.artist?.name ?? "", name: album.name),
                hint: album.imageURL,
                placeholderSymbol: "opticaldisc.fill"
            )
            .frame(width: 40, height: 40)

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

private struct ChartTrackRow: View {
    var track: LastFMTrack
    var rank: Int

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            RankBadge(rank: rank)

            AsyncArtwork(
                subject: .track(artist: track.artist.name, title: track.name),
                hint: track.imageURL,
                placeholderSymbol: "music.note"
            )
            .frame(width: 40, height: 40)

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

private struct RankBadge: View {
    var rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.callout.weight(.semibold))
            .foregroundStyle(rankColor)
            .monospacedDigit()
            .frame(width: 28, alignment: .trailing)
    }

    private var rankColor: Color {
        switch rank {
        case 1: .yellow
        case 2, 3: .secondary
        default: Color(nsColor: .tertiaryLabelColor)
        }
    }
}
