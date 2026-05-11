import Core
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                localCard
                if !visibleRemoteEntries.isEmpty {
                    sectionTitle("Playing on Other Devices")
                    ForEach(visibleRemoteEntries) { entry in
                        remoteCard(entry)
                    }
                }
                metricsRow
                if model.status.data != nil {
                    trackDetails
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
        .onDisappear {
            model.stopRemoteNowPlayingPolling()
        }
    }

    // MARK: - Computed

    /// Remote entries minus any that duplicate what's playing locally on the Mac.
    private var visibleRemoteEntries: [RemoteNowPlayingEntry] {
        guard let local = model.status.data, model.status.state == .playing else {
            return model.remoteNowPlaying
        }
        return model.remoteNowPlaying.filter { !$0.matchesLocal(local) }
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
        if let data = model.status.data {
            HStack(spacing: Layout.sectionSpacing) {
                localArtwork(for: data)
                trackInfo(
                    title: data.track,
                    artist: data.artist,
                    album: data.album,
                    source: "This Mac" + (data.appName.map { " · \($0)" } ?? "")
                )
                Spacer(minLength: 0)
                AnimatedEqualizer(
                    isPlaying: model.status.state == .playing,
                    color: .accentColor
                )
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

    // MARK: - Metrics

    private var metricsRow: some View {
        GroupBox {
            Grid(horizontalSpacing: Layout.sectionSpacing, verticalSpacing: 0) {
                GridRow {
                    metric(
                        icon: "circle.fill",
                        iconColor: model.status.state.indicatorColor,
                        title: "State",
                        value: model.status.state.displayLabel
                    )
                    Divider()
                    metric(
                        icon: "person.2.fill",
                        iconColor: .secondary,
                        title: "Accounts",
                        value: "\(model.accounts.filter(\.enabled).count)"
                    )
                    Divider()
                    metric(
                        icon: "tray.full.fill",
                        iconColor: model.pendingCount > 0 ? .orange : .secondary,
                        title: "Pending",
                        value: "\(model.pendingCount)"
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metric(icon: String, iconColor: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Track Details

    @ViewBuilder
    private var trackDetails: some View {
        if let data = model.status.data {
            GroupBox("Track Details") {
                VStack(spacing: 0) {
                    detailRow("Album", value: data.album ?? "—")
                    Divider()
                    detailRow("Album Artist", value: data.albumArtist ?? "—")
                    Divider()
                    detailRow("App", value: data.appName ?? data.appID ?? "—")
                    Divider()
                    detailRow("Started", value: data.timestamp.formatted(date: .omitted, time: .standard))
                    if let duration = data.duration {
                        Divider()
                        detailRow("Duration", value: formatDuration(duration))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.sectionSpacing) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
        .padding(.vertical, 6)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
