import Core
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var model: AppModel
    @State private var selectedInfoTrack: LastFMTrack?
    @State private var editEntry: NowPlayingCardEntry?
    @State private var lovedStates: [String: Bool] = [:]
    @State private var locallyChangedLoveEntryIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                nowPlayingCard
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSubtitle(activeEntry == nil ? "Idle" : "Scrobbling")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshRemoteNowPlaying() }
                } label: {
                    if model.isRefreshingRemoteNowPlaying {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isRefreshingRemoteNowPlaying)
                .help("Refresh now-playing")
            }
        }
        .animation(.default, value: model.status.data?.stableIdentity)
        .animation(.default, value: model.remoteNowPlaying)
        .task {
            model.startRemoteNowPlayingPolling()
        }
        .task(id: localRefreshID) {
            await model.refreshRemoteNowPlaying()
        }
        .task(id: activeEntry?.id ?? "idle") {
            await refreshLovedState()
        }
        .sheet(item: $selectedInfoTrack) { track in
            MusicEntryInfoView(model: model, track: track, album: nil, artist: nil)
        }
        .sheet(item: $editEntry) { entry in
            NowPlayingEditSheet(model: model, entry: entry)
        }
    }

    private var activeEntry: NowPlayingCardEntry? {
        if let remote = model.remoteNowPlaying.first {
            return NowPlayingCardEntry(remote: remote)
        }
        if let data = model.status.data, model.status.state == .playing {
            return NowPlayingCardEntry(local: data)
        }
        return nil
    }

    private var localRefreshID: String {
        [
            model.status.state.rawValue,
            model.status.data?.stableIdentity ?? "none"
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var nowPlayingCard: some View {
        if let entry = activeEntry {
            activeCard(entry)
        } else {
            idleCard
        }
    }

    private func activeCard(_ entry: NowPlayingCardEntry) -> some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: .track(artist: entry.artist, title: entry.track),
                hint: entry.artworkURL,
                placeholderSymbol: "music.note",
                cornerRadius: 10
            )
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(entry.track)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(entry.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = entry.album, !album.isEmpty {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Layout.inlineSpacing) {
                let isLoved = lovedStates[entry.id] == true

                PulsingDot(color: .green, size: 9, isPulsing: true)
                    .help("Scrobbling")

                Button {
                    love(entry)
                } label: {
                    Image(systemName: isLoved ? "heart.fill" : "heart")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isLoved ? .red : .secondary)
                .help(isLoved ? "Unlove track" : "Love track")

                Button {
                    editEntry = entry
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Add edit rule")
            }
        }
        .heroGlass()
        .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .onTapGesture {
            selectedInfoTrack = entry.lastFMTrack
        }
        .transition(.blurReplace)
    }

    private var idleCard: some View {
        HStack(spacing: Layout.sectionSpacing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.tertiary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Idle")
                    .font(.title2.weight(.semibold))
                Text("No current scrobble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Play something locally or refresh to check connected services.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            PulsingDot(color: .secondary, size: 9, isPulsing: false)
        }
        .padding(Layout.sectionSpacing)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func love(_ entry: NowPlayingCardEntry) {
        let nextState = !(lovedStates[entry.id] ?? false)
        lovedStates[entry.id] = nextState
        locallyChangedLoveEntryIDs.insert(entry.id)
        Task {
            await model.toggleLove(artist: entry.artist, track: entry.track, loved: nextState)
        }
    }

    private func refreshLovedState() async {
        guard let entry = activeEntry else { return }
        await refreshLovedState(for: entry)
    }

    private func refreshLovedState(for entry: NowPlayingCardEntry) async {
        guard let service = model.lastFMService else { return }
        do {
            let info = try await service.getTrackInfo(artist: entry.artist, track: entry.track)
            guard !locallyChangedLoveEntryIDs.contains(entry.id) else { return }
            lovedStates[entry.id] = info.userloved?.boolValue == true
        } catch {
            // Leave the current local state alone if the service is unavailable.
        }
    }
}

private struct NowPlayingCardEntry: Identifiable, Equatable {
    var id: String
    var source: String
    var artist: String
    var track: String
    var album: String?
    var artworkURL: URL?
    var timestamp: Date?

    init(local data: ScrobbleData) {
        self.id = "local|\(data.stableIdentity)"
        self.source = "This Mac" + (data.appName.map { " · \($0)" } ?? "")
        self.artist = data.artist
        self.track = data.track
        self.album = data.album
        self.artworkURL = data.artworkURL
        self.timestamp = data.timestamp
    }

    init(remote entry: RemoteNowPlayingEntry) {
        self.id = entry.id
        self.source = "\(entry.sourceDisplayName) · \(entry.username)"
        self.artist = entry.artist
        self.track = entry.track
        self.album = entry.album
        self.artworkURL = entry.artworkURL
        self.timestamp = entry.since
    }

    var lastFMTrack: LastFMTrack {
        LastFMTrack(
            name: track,
            artist: LastFMArtist(name: artist),
            album: album.map { LastFMAlbum(name: $0, artist: LastFMArtist(name: artist)) },
            image: artworkURL.map { [LastFMImage(size: "extralarge", url: $0.absoluteString)] }
        )
    }
}

private struct NowPlayingEditSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: NowPlayingCardEntry

    @State private var matchArtist: String
    @State private var matchTrack: String
    @State private var replacementArtist: String
    @State private var replacementTrack: String
    @State private var replacementAlbum: String
    @State private var replacementAlbumArtist: String

    init(model: AppModel, entry: NowPlayingCardEntry) {
        self.model = model
        self.entry = entry
        _matchArtist = State(initialValue: entry.artist)
        _matchTrack = State(initialValue: entry.track)
        _replacementArtist = State(initialValue: entry.artist)
        _replacementTrack = State(initialValue: entry.track)
        _replacementAlbum = State(initialValue: entry.album ?? "")
        _replacementAlbumArtist = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            Text("Edit Scrobble")
                .font(.title3.weight(.semibold))

            Form {
                Section("Match") {
                    TextField("Artist", text: $matchArtist)
                    TextField("Track", text: $matchTrack)
                }

                Section("Replace With") {
                    TextField("Artist", text: $replacementArtist)
                    TextField("Track", text: $replacementTrack)
                    TextField("Album", text: $replacementAlbum)
                    TextField("Album artist", text: $replacementAlbumArtist)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .standardGlassButton()

                Button {
                    model.addSimpleEdit(
                        matchArtist: matchArtist,
                        matchTrack: matchTrack,
                        replacementArtist: replacementArtist,
                        replacementTrack: replacementTrack,
                        replacementAlbum: replacementAlbum,
                        replacementAlbumArtist: replacementAlbumArtist
                    )
                    dismiss()
                } label: {
                    Label("Save Edit", systemImage: "checkmark")
                }
                .disabled(matchArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matchTrack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .prominentGlassButton()
            }
        }
        .padding(Layout.windowPadding)
        .frame(width: 460, height: 460)
    }
}
