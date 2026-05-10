import SwiftUI
import Core
import Services

/// A sheet that shows detailed info about a track, album, or artist.
/// Mirrors the Kotlin `MusicEntryInfoDialog` with tags, stats, wiki, similar items, and actions.
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

    // UI state
    @State private var showWiki = false
    @State private var selectedInfoTab: InfoTab = .overview

    enum InfoTab: String, CaseIterable {
        case overview = "Overview"
        case similar = "Similar"
        case topTracks = "Top Tracks"
        case topAlbums = "Top Albums"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading {
                loadingView
            } else if let error {
                errorView(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
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
                    .padding(Spacing.lg)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 600)
        .task { await loadInfo() }
    }

    // MARK: - Header

    private var headerBar: some View {
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
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(Spacing.md)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HStack(spacing: Spacing.lg) {
            // Artwork
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    artworkPlaceholder
                default:
                    artworkPlaceholder
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Spacing.sm) {
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
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                if let loved = trackInfo?.userloved?.boolValue, loved {
                    Label("Loved", systemImage: "heart.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AccentColors.error)
                }
            }

            Spacer()
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: track != nil ? "music.note" : album != nil ? "square.stack" : "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: Spacing.xl) {
            if let userPlaycount = userPlaycount, userPlaycount > 0 {
                statItem(value: formatCount(userPlaycount), label: "Your Plays", icon: "person.fill")
            }
            if let listeners = listenersCount, listeners > 0 {
                statItem(value: formatCount(listeners), label: "Listeners", icon: "person.2.fill")
            }
            if let playcount = globalPlaycount, playcount > 0 {
                statItem(value: formatCount(playcount), label: "Scrobbles", icon: "music.note.list")
            }
            Spacer()
        }
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private var tagsSection: some View {
        let tags = allTags
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Tags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(tags.prefix(10)) { tag in
                        Text(tag.name)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AccentColors.primary.opacity(0.1), in: Capsule())
                            .foregroundStyle(AccentColors.primary)
                    }
                }
            }
        }
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: Spacing.sm) {
            if track != nil, let trackInfo {
                // Love / Unlove button
                Button {
                    Task {
                        let isLoved = trackInfo.userloved?.boolValue ?? false
                        await model.toggleLove(
                            artist: trackInfo.artist?.name ?? track?.artist.name ?? "",
                            track: trackInfo.name,
                            loved: !isLoved
                        )
                        // Refresh
                        await loadInfo()
                    }
                } label: {
                    let isLoved = trackInfo.userloved?.boolValue ?? false
                    Label(isLoved ? "Unlove" : "Love", systemImage: isLoved ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let url = entryURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                let text = [entrySubtitle, entryName].compactMap { $0 }.joined(separator: " — ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
    }

    // MARK: - Track-specific Content

    @ViewBuilder
    private var trackInfoContent: some View {
        // Wiki
        if let wiki = trackInfo?.wiki?.content, !wiki.isEmpty {
            wikiSection(wiki)
        }

        // Similar tracks
        if !similarTracks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Similar Tracks", icon: "music.note")

                ForEach(similarTracks.prefix(8)) { similar in
                    HStack(spacing: Spacing.sm) {
                        AsyncImage(url: similar.imageURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.1)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(similar.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(similar.artist?.name ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }

                        Spacer()

                        if let match = similar.match {
                            Text("\(Int(match * 100))%")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Album-specific Content

    @ViewBuilder
    private var albumInfoContent: some View {
        if let wiki = albumInfo?.wiki?.content, !wiki.isEmpty {
            wikiSection(wiki)
        }

        // Track list
        if let tracks = albumInfo?.tracks?.track, !tracks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Tracks (\(tracks.count))", icon: "list.number")

                ForEach(tracks) { entry in
                    HStack(spacing: Spacing.sm) {
                        Text("\(entry.rank?.intValue ?? 0)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)

                        Text(entry.name)
                            .font(.system(size: 12))
                            .lineLimit(1)

                        Spacer()

                        if let dur = entry.duration?.intValue, dur > 0 {
                            Text(formatDuration(dur))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Artist-specific Content

    @ViewBuilder
    private var artistInfoContent: some View {
        if let bio = artistInfo?.bio?.content, !bio.isEmpty {
            wikiSection(bio)
        }

        // Top tracks
        if !artistTopTracks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Top Tracks", icon: "music.note")

                ForEach(Array(artistTopTracks.prefix(8).enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(index < 3 ? AccentColors.primary : .secondary)
                            .frame(width: 20, alignment: .trailing)

                        AsyncImage(url: track.imageURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.1)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text(track.name)
                            .font(.system(size: 12))
                            .lineLimit(1)

                        Spacer()

                        if let pc = track.playcount?.intValue {
                            Text(formatCount(pc))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }

        // Top albums
        if !artistTopAlbums.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Top Albums", icon: "square.stack")

                ForEach(Array(artistTopAlbums.prefix(6).enumerated()), id: \.element.id) { index, album in
                    HStack(spacing: Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(index < 3 ? AccentColors.secondary : .secondary)
                            .frame(width: 20, alignment: .trailing)

                        AsyncImage(url: album.imageURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.1)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        Text(album.name)
                            .font(.system(size: 12))
                            .lineLimit(1)

                        Spacer()

                        if let pc = album.playcount?.intValue {
                            Text(formatCount(pc))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }

        // Similar artists
        if !similarArtists.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Similar Artists", icon: "person.2")

                FlowLayout(spacing: 8) {
                    ForEach(similarArtists.prefix(10)) { artist in
                        HStack(spacing: 4) {
                            AsyncImage(url: artist.imageURL) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.secondary.opacity(0.15)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())

                            Text(artist.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(AccentColors.primary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.top, Spacing.sm)
    }

    private func wikiSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("About", icon: "text.alignleft")

            let cleaned = text
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Text(cleaned)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(showWiki ? nil : 4)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showWiki.toggle() } }

            if cleaned.count > 200 {
                Button(showWiki ? "Show Less" : "Read More…") {
                    withAnimation(.easeInOut(duration: 0.2)) { showWiki.toggle() }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
                .foregroundStyle(AccentColors.primary)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading info…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadInfo() } }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Computed Properties

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
        trackInfo?.userplaycount?.intValue ?? albumInfo?.userplaycount?.intValue ?? artistInfo?.userplaycount?.intValue
    }

    private var listenersCount: Int? {
        trackInfo?.listeners?.intValue ?? albumInfo?.listeners?.intValue ?? artistInfo?.listeners?.intValue
    }

    private var globalPlaycount: Int? {
        trackInfo?.playcount?.intValue ?? albumInfo?.playcount?.intValue ?? artistInfo?.playcount?.intValue
    }

    private var allTags: [LastFMTag] {
        trackInfo?.toptags?.tag ?? albumInfo?.tags?.tag ?? artistInfo?.tags?.tag ?? []
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

// MARK: - Flow Layout

/// A simple flow layout that wraps children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = computeLayout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }
}
