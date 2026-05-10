import SwiftUI
import Core

struct ScrobbleHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTrack: LastFMTrack?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                trackList
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            if model.scrobbleHistory.isEmpty {
                model.loadHistory()
            }
        }
        .sheet(item: $selectedTrack) { track in
            MusicEntryInfoView(model: model, track: track, album: nil, artist: nil)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Scrobble History")
                    .font(.displayLarge)

                if model.historyPage.total > 0 {
                    Text("\(model.historyPage.total) total scrobbles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.loadHistory(page: 1)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingHistory)
        }
    }

    // MARK: - Track List

    @ViewBuilder
    private var trackList: some View {
        if model.isLoadingHistory && model.scrobbleHistory.isEmpty {
            ProgressView("Loading scrobbles…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
        } else if model.scrobbleHistory.isEmpty {
            ContentUnavailableView(
                "No Scrobbles",
                systemImage: "clock.arrow.circlepath",
                description: Text("Add a Last.fm account and start listening to music.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(model.scrobbleHistory) { track in
                    TrackRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTrack = track }
                        .contextMenu {
                            Button {
                                selectedTrack = track
                            } label: {
                                Label("Info", systemImage: "info.circle")
                            }

                            if let url = track.url.flatMap({ URL(string: $0) }) {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("Open in Browser", systemImage: "safari")
                                }
                            }

                            Button {
                                let text = "\(track.artist.name) — \(track.name)"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Button {
                                Task {
                                    let isLoved = track.loved?.boolValue == true
                                    await model.toggleLove(
                                        artist: track.artist.name,
                                        track: track.name,
                                        loved: !isLoved
                                    )
                                }
                            } label: {
                                Label(
                                    track.loved?.boolValue == true ? "Unlove" : "Love",
                                    systemImage: track.loved?.boolValue == true ? "heart.slash" : "heart"
                                )
                            }

                            Divider()

                            if let timestamp = track.timestamp, !track.isNowPlaying {
                                Button(role: .destructive) {
                                    Task {
                                        await model.deleteScrobble(
                                            artist: track.artist.name,
                                            track: track.name,
                                            timestamp: timestamp
                                        )
                                    }
                                } label: {
                                    Label("Delete Scrobble", systemImage: "trash")
                                }
                            }
                        }
                }

                if model.historyPage.page < model.historyPage.totalPages {
                    loadMoreButton
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            model.loadHistory(page: model.historyPage.page + 1)
        } label: {
            if model.isLoadingHistory {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Load More")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .disabled(model.isLoadingHistory)
    }
}

// MARK: - Track Row

struct TrackRow: View {
    var track: LastFMTrack

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                artworkView
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(track.artist.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let albumName = track.album?.name, !albumName.isEmpty {
                        Text(albumName)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if track.isNowPlaying {
                        HStack(spacing: 4) {
                            PulsingDot(color: AccentColors.success, size: 6, isPulsing: true)
                            Text("Now")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AccentColors.success)
                        }
                    } else if let date = track.timestamp {
                        Text(date, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if track.loved?.boolValue == true {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let url = track.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    artworkPlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
    }
}
