import Core
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                localCard
                if !visibleRemoteEntries.isEmpty {
                    sectionTitle("Current Scrobblings")
                    ForEach(visibleRemoteEntries) { entry in
                        remoteCard(entry)
                    }
                }
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSubtitle(navSubtitle)
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
                .help("Refresh remote now-playing")
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
        .onDisappear {
            model.stopRemoteNowPlayingPolling()
        }
    }

    // MARK: - Computed

    private var visibleRemoteEntries: [RemoteNowPlayingEntry] {
        model.remoteNowPlaying
    }

    private var localRefreshID: String {
        [
            model.status.state.rawValue,
            model.status.data?.stableIdentity ?? "none"
        ].joined(separator: "|")
    }

    private var navSubtitle: String {
        let local = model.status.state.displayLabel
        let remoteCount = visibleRemoteEntries.count
        if remoteCount > 0 {
            return "\(local) · \(remoteCount) remote"
        }
        return local
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: - Local card (This Mac)

    @ViewBuilder
    private var localCard: some View {
        if let data = model.status.data, model.status.state == .playing {
            HStack(spacing: Layout.sectionSpacing) {
                localArtwork(for: data)
                trackInfo(
                    title: data.track,
                    artist: data.artist,
                    album: data.album,
                    source: "This Mac" + (data.appName.map { " · \($0)" } ?? "")
                )
                Spacer(minLength: 0)
                PulsingDot(color: .green, size: 9, isPulsing: true)
            }
            .heroGlass()
            .transition(.blurReplace)
        } else {
            idleLocalCard
        }
    }

    private var idleLocalCard: some View {
        HStack(spacing: Layout.sectionSpacing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.tertiary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "laptopcomputer")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("This Mac")
                    .font(.headline)
                Text(model.status.state.displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Play something in Music, Spotify, or any supported app.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.sectionSpacing)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func localArtwork(for data: ScrobbleData) -> some View {
        AsyncArtwork(
            subject: .track(artist: data.artist, title: data.track),
            hint: data.artworkURL,
            placeholderSymbol: "music.note",
            cornerRadius: 10
        )
        .frame(width: 96, height: 96)
    }

    private func trackInfo(title: String, artist: String, album: String?, source: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .contentTransition(.numericText())
            Text(artist)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let album {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Remote card

    private func remoteCard(_ entry: RemoteNowPlayingEntry) -> some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: .track(artist: entry.artist, title: entry.track),
                hint: entry.artworkURL,
                placeholderSymbol: "music.note",
                cornerRadius: 10
            )
            .frame(width: 80, height: 80)

            trackInfo(
                title: entry.track,
                artist: entry.artist,
                album: entry.album,
                source: "\(entry.sourceDisplayName) · \(entry.username)"
            )

            Spacer(minLength: 0)

            PulsingDot(color: .green, size: 8, isPulsing: true)
        }
        .padding(Layout.sectionSpacing)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .transition(.blurReplace)
    }

}
