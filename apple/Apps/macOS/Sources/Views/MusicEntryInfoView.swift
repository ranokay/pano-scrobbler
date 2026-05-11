import AppKit
import Core
import Services
import SwiftUI

/// A sheet that shows detailed info about a track, album, or artist.
struct MusicEntryInfoView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var error: String?

    // Which entry are we showing?
    let track: LastFMTrack?
    let album: LastFMAlbum?
    let artist: LastFMArtist?

    // Loaded info
    @State private var trackInfo: LastFMTrackInfo?
    @State private var albumInfo: LastFMAlbumInfo?
    @State private var artistInfo: LastFMArtistInfo?
    @State private var similarTracks: [LastFMSimilarTrack] = []
    @State private var similarArtists: [LastFMArtist] = []
    @State private var artistTopTracks: [LastFMTrack] = []
    @State private var artistTopAlbums: [LastFMAlbum] = []

    @State private var showWiki = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if isLoading {
                    loadingView
                } else if let error {
                    errorView(error)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                            heroSection
                            statsSection
                            tagsSection
                            actionsRow

                            if trackInfo != nil {
                                trackInfoContent
                            } else if albumInfo != nil {
                                albumInfoContent
                            } else if artistInfo != nil {
                                artistInfoContent
                            }
                        }
                        .padding(Layout.windowPadding)
                    }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 460, idealHeight: 640)
        .task { await loadInfo() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entryName)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = entrySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .standardGlassButton()
        }
        .padding(Layout.windowPadding)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: heroArtworkSubject,
                hint: artworkURL,
                placeholderSymbol: heroPlaceholderSymbol,
                cornerRadius: 12
            )
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                Text(entryName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = entrySubtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let duration = formattedDuration {
                    Label(duration, systemImage: "clock")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                if let loved = trackInfo?.userloved?.boolValue, loved {
                    Label("Loved", systemImage: "heart.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .heroGlass()
    }

    private var heroPlaceholderSymbol: String {
        if track != nil { return "music.note" }
        if album != nil { return "square.stack" }
        return "person.fill"
    }

    private var heroArtworkSubject: ArtworkCache.Subject {
        if let t = track {
            return .track(artist: t.artist.name, title: t.name)
        }
        if let a = album {
            return .album(artist: a.artist?.name ?? "", name: a.name)
        }
        if let ar = artist {
            return .artist(name: ar.name)
        }
        return .artist(name: entryName)
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: Layout.sectionSpacing * 1.5) {
            if let userPlaycount, userPlaycount > 0 {
                statItem(value: formatCount(userPlaycount), label: "Your Plays", icon: "person.fill")
            }
            if let listenersCount, listenersCount > 0 {
                statItem(value: formatCount(listenersCount), label: "Listeners", icon: "person.2.fill")
            }
            if let globalPlaycount, globalPlaycount > 0 {
                statItem(value: formatCount(globalPlaycount), label: "Scrobbles", icon: "music.note.list")
            }
            Spacer()
        }
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(value, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        let tags = allTags
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                Text("Tags")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(tags.prefix(10)) { tag in
                        Text(tag.name)
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.12), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: Layout.inlineSpacing) {
            if track != nil, let trackInfo {
                Button {
                    Task {
                        let isLoved = trackInfo.userloved?.boolValue ?? false
                        await model.toggleLove(
                            artist: trackInfo.artist?.name ?? track?.artist.name ?? "",
                            track: trackInfo.name,
                            loved: !isLoved
                        )
                        await loadInfo()
                    }
                } label: {
                    let isLoved = trackInfo.userloved?.boolValue ?? false
                    Label(isLoved ? "Unlove" : "Love",
                          systemImage: isLoved ? "heart.fill" : "heart")
                }
            }

            if let url = entryURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }

            Button {
                let text = [entrySubtitle, entryName].compactMap { $0 }.joined(separator: " — ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Spacer()
        }
        .controlSize(.regular)
    }

    // MARK: - Type-specific Content

    @ViewBuilder
    private var trackInfoContent: some View {
        if let wiki = trackInfo?.wiki?.content, !wiki.isEmpty {
            wikiSection(wiki)
        }

        if !similarTracks.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Similar Tracks", systemImage: "music.note")
                        .font(.headline)
                        .padding(.bottom, Layout.inlineSpacing)

                    ForEach(Array(similarTracks.prefix(8).enumerated()), id: \.element.id) { index, similar in
                        similarTrackRow(similar)
                        if index < min(similarTracks.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func similarTrackRow(_ similar: LastFMSimilarTrack) -> some View {
        HStack(spacing: Layout.inlineSpacing) {
            AsyncArtwork(
                subject: .track(artist: similar.artist?.name ?? "", title: similar.name),
                hint: similar.imageURL,
                placeholderSymbol: "music.note"
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(similar.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(similar.artist?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let match = similar.match {
                Text("\(Int(match * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var albumInfoContent: some View {
        if let wiki = albumInfo?.wiki?.content, !wiki.isEmpty {
            wikiSection(wiki)
        }

        if let tracks = albumInfo?.tracks?.track, !tracks.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Tracks (\(tracks.count))", systemImage: "list.number")
                        .font(.headline)
                        .padding(.bottom, Layout.inlineSpacing)

                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: Layout.inlineSpacing) {
                            Text("\(entry.rank?.intValue ?? 0)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)

                            Text(entry.name)
                                .font(.callout)
                                .lineLimit(1)

                            Spacer()

                            if let dur = entry.duration?.intValue, dur > 0 {
                                Text(formatDuration(dur))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        if index < tracks.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var artistInfoContent: some View {
        if let bio = artistInfo?.bio?.content, !bio.isEmpty {
            wikiSection(bio)
        }

        if !artistTopTracks.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Top Tracks", systemImage: "music.note")
                        .font(.headline)
                        .padding(.bottom, Layout.inlineSpacing)

                    ForEach(Array(artistTopTracks.prefix(8).enumerated()), id: \.element.id) { index, track in
                        topRow(
                            rank: index + 1,
                            subject: .track(artist: track.artist.name, title: track.name),
                            hint: track.imageURL,
                            placeholder: "music.note",
                            name: track.name,
                            plays: track.playcount?.intValue
                        )
                        if index < min(artistTopTracks.count, 8) - 1 { Divider() }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        if !artistTopAlbums.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Top Albums", systemImage: "square.stack")
                        .font(.headline)
                        .padding(.bottom, Layout.inlineSpacing)

                    ForEach(Array(artistTopAlbums.prefix(6).enumerated()), id: \.element.id) { index, album in
                        topRow(
                            rank: index + 1,
                            subject: .album(artist: album.artist?.name ?? "", name: album.name),
                            hint: album.imageURL,
                            placeholder: "opticaldisc.fill",
                            name: album.name,
                            plays: album.playcount?.intValue
                        )
                        if index < min(artistTopAlbums.count, 6) - 1 { Divider() }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        if !similarArtists.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                    Label("Similar Artists", systemImage: "person.2")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(similarArtists.prefix(10)) { artist in
                            HStack(spacing: 4) {
                                AsyncArtwork(
                                    subject: .artist(name: artist.name),
                                    hint: artist.imageURL,
                                    placeholderSymbol: "person.fill",
                                    cornerRadius: 12
                                )
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(.callout)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.background.tertiary, in: Capsule())
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func topRow(
        rank: Int,
        subject: ArtworkCache.Subject,
        hint: URL?,
        placeholder: String,
        name: String,
        plays: Int?
    ) -> some View {
        HStack(spacing: Layout.inlineSpacing) {
            Text("\(rank)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.accentColor : Color.secondary)
                .frame(width: 24, alignment: .trailing)

            AsyncArtwork(
                subject: subject,
                hint: hint,
                placeholderSymbol: placeholder,
                cornerRadius: 5
            )
            .frame(width: 32, height: 32)

            Text(name)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            if let pc = plays {
                Text(formatCount(pc))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Wiki

    private func wikiSection(_ text: String) -> some View {
        let cleaned = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return GroupBox {
            VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                Label("About", systemImage: "text.alignleft")
                    .font(.headline)

                Text(cleaned)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(showWiki ? nil : 4)
                    .textSelection(.enabled)

                if cleaned.count > 200 {
                    Button(showWiki ? "Show Less" : "Read More…") {
                        withAnimation(.easeInOut(duration: 0.2)) { showWiki.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.callout.weight(.medium))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Layout.sectionSpacing) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Loading info…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Info", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await loadInfo() } }
        }
    }

    // MARK: - Data Loading

    private func loadInfo() async {
        isLoading = true
        error = nil

        do {
            guard let service = model.lastFMService else {
                error = "No Last.fm account connected."
                isLoading = false
                return
            }

            if let t = track {
                async let infoTask = service.getTrackInfo(artist: t.artist.name, track: t.name)
                async let similarTask = service.getSimilarTracks(artist: t.artist.name, track: t.name)

                let (info, similar) = try await (infoTask, similarTask)
                trackInfo = info
                similarTracks = similar
            } else if let a = album {
                let info = try await service.getAlbumInfo(
                    artist: a.artist?.name ?? "",
                    album: a.name
                )
                albumInfo = info
            } else if let ar = artist {
                async let infoTask = service.getArtistInfo(artist: ar.name)
                async let topTracksTask = service.getArtistTopTracks(artist: ar.name)
                async let topAlbumsTask = service.getArtistTopAlbums(artist: ar.name)

                let (info, topTr, topAl) = try await (infoTask, topTracksTask, topAlbumsTask)
                artistInfo = info
                artistTopTracks = topTr
                artistTopAlbums = topAl
                similarArtists = info.similar?.artist ?? []
            }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Computed

    private var entryName: String {
        track?.name ?? album?.name ?? artist?.name ?? "Unknown"
    }

    private var entrySubtitle: String? {
        if track != nil { return track?.artist.name }
        if let album, let artist = album.artist { return artist.name }
        return nil
    }

    private var artworkURL: URL? {
        if let track { return track.imageURL }
        if let album { return album.imageURL ?? albumInfo?.imageURL }
        if let artist { return artist.imageURL ?? artistInfo?.imageURL }
        return nil
    }

    private var entryURL: URL? {
        if let urlString = trackInfo?.url { return URL(string: urlString) }
        if let urlString = albumInfo?.url { return URL(string: urlString) }
        if let urlString = artistInfo?.url { return URL(string: urlString) }
        if let urlString = track?.url { return URL(string: urlString) }
        if let urlString = album?.url { return URL(string: urlString) }
        if let urlString = artist?.url { return URL(string: urlString) }
        return nil
    }

    private var userPlaycount: Int? {
        trackInfo?.userplaycount?.intValue
            ?? albumInfo?.userplaycount?.intValue
            ?? artistInfo?.userplaycount?.intValue
    }

    private var listenersCount: Int? {
        trackInfo?.listeners?.intValue
            ?? albumInfo?.listeners?.intValue
            ?? artistInfo?.listeners?.intValue
    }

    private var globalPlaycount: Int? {
        trackInfo?.playcount?.intValue
            ?? albumInfo?.playcount?.intValue
            ?? artistInfo?.playcount?.intValue
    }

    private var allTags: [LastFMTag] {
        trackInfo?.toptags?.tag
            ?? albumInfo?.tags?.tag
            ?? artistInfo?.tags?.tag
            ?? []
    }

    private var formattedDuration: String? {
        guard let secs = trackInfo?.durationSeconds, secs > 0 else { return nil }
        let min = secs / 60
        let sec = secs % 60
        return String(format: "%d:%02d", min, sec)
    }

    // MARK: - Helpers

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%d:%02d", min, sec)
    }
}
