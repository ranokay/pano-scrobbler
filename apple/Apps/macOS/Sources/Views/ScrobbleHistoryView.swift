import AppKit
import Core
import SwiftUI

struct ScrobbleHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTrack: LastFMTrack?

    var body: some View {
        Group {
            if model.isLoadingHistory && model.scrobbleHistory.isEmpty {
                ProgressView("Loading scrobbles…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.scrobbleHistory.isEmpty {
                ContentUnavailableView(
                    "No Scrobbles",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Add a Last.fm account and start listening to music.")
                )
            } else {
                trackList
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.loadHistory(page: 1)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingHistory)
            }
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

    private var subtitle: String {
        if model.historyPage.total > 0 {
            return "\(model.historyPage.total.formatted()) scrobbles"
        }
        return ""
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            Section {
                ForEach(model.scrobbleHistory.filter { !$0.isNowPlaying }) { track in
                    TrackRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTrack = track }
                        .contextMenu {
                            trackMenu(for: track)
                        }
                }

                if model.historyPage.page < model.historyPage.totalPages {
                    HStack {
                        Spacer()
                        Button {
                            model.loadHistory(page: model.historyPage.page + 1)
                        } label: {
                            if model.isLoadingHistory {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Load More")
                            }
                        }
                        .disabled(model.isLoadingHistory)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func trackMenu(for track: LastFMTrack) -> some View {
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

        if let timestamp = track.timestamp {
            Divider()
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

// MARK: - Track Row

struct TrackRow: View {
    var track: LastFMTrack

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
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

                if let albumName = track.album?.name, !albumName.isEmpty {
                    Text(albumName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if track.isNowPlaying {
                    HStack(spacing: 4) {
                        PulsingDot(color: .green, size: 6, isPulsing: true)
                        Text("Now")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else if let date = track.timestamp {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if track.loved?.boolValue == true {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
