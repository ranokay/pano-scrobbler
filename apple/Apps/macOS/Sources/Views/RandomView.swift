import AppKit
import Core
import Services
import SwiftUI

/// Picks a random entry from the user's library.
struct RandomView: View {
    @ObservedObject var model: AppModel
    @State private var selectedType: RandomType = .tracks
    @State private var period: LastFMPeriod = .overall
    @State private var result: RandomResult?
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedTrack: LastFMTrack?

    enum RandomType: String, CaseIterable {
        case tracks = "Tracks"
        case artists = "Artists"
        case albums = "Albums"
        case loved = "Loved"

        var icon: String {
            switch self {
            case .tracks: "music.note"
            case .artists: "person.fill"
            case .albums: "square.stack"
            case .loved: "heart.fill"
            }
        }
    }

    struct RandomResult {
        var name: String
        var subtitle: String?
        var imageURL: URL?
        var url: String?
        var playcount: Int?
        var track: LastFMTrack?
        var album: LastFMAlbum?
        var artist: LastFMArtist?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                controlsCard
                resultView
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $selectedTrack) { track in
            MusicEntryInfoView(model: model, track: track, album: nil, artist: nil)
        }
    }

    // MARK: - Controls

    private var controlsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                Picker("Type", selection: $selectedType) {
                    ForEach(RandomType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: Layout.sectionSpacing) {
                    if selectedType != .loved {
                        Picker("Period", selection: $period) {
                            ForEach(LastFMPeriod.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .frame(maxWidth: 220)
                    }

                    Spacer()

                    Button {
                        Task { await loadRandom() }
                    } label: {
                        Label("Roll", systemImage: "dice.fill")
                    }
                    .prominentGlassButton()
                    .disabled(isLoading)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultView: some View {
        if isLoading {
            VStack(spacing: Layout.sectionSpacing) {
                ProgressView().controlSize(.large)
                Text("Finding something…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if let error {
            ContentUnavailableView(
                "No Result",
                systemImage: "dice",
                description: Text(error)
            )
            .padding(.vertical, 40)
        } else if let result {
            resultCard(result)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .opacity
                ))
        } else {
            ContentUnavailableView(
                "Press Roll",
                systemImage: "dice",
                description: Text("Discover a random entry from your library.")
            )
            .padding(.vertical, 40)
        }
    }

    private func resultCard(_ result: RandomResult) -> some View {
        HStack(spacing: Layout.sectionSpacing) {
            AsyncArtwork(
                subject: artworkSubject(for: result),
                hint: result.imageURL,
                placeholderSymbol: selectedType.icon,
                cornerRadius: 12
            )
            .frame(width: 160, height: 160)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                Text(result.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let pc = result.playcount, pc > 0 {
                    Label("\(pc.formatted()) plays", systemImage: "play.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: Layout.inlineSpacing) {
                    if let track = result.track {
                        Button {
                            selectedTrack = track
                        } label: {
                            Label("Info", systemImage: "info.circle")
                        }
                    }

                    if let urlStr = result.url, let url = URL(string: urlStr) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open", systemImage: "safari")
                        }
                    }

                    Button {
                        Task { await loadRandom() }
                    } label: {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .prominentGlassButton()
                }
                .controlSize(.regular)
            }
        }
        .heroGlass()
    }

    private func artworkSubject(for result: RandomResult) -> ArtworkCache.Subject {
        if let artist = result.artist {
            return .artist(name: artist.name)
        }
        if let album = result.album {
            return .album(artist: album.artist?.name ?? "", name: album.name)
        }
        if let track = result.track {
            return .track(artist: track.artist.name, title: track.name)
        }
        return .artist(name: result.name)
    }

    // MARK: - Data Loading

    private func loadRandom() async {
        guard let service = model.lastFMService else {
            error = "No Last.fm account connected."
            return
        }

        isLoading = true
        error = nil

        do {
            withAnimation(.easeInOut(duration: 0.2)) { result = nil }

            switch selectedType {
            case .tracks:
                let response = try await service.getTopTracks(period: period, limit: 50)
                guard let entry = response.entries.randomElement() else {
                    error = "No tracks found for this period."
                    isLoading = false
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    result = RandomResult(
                        name: entry.name,
                        subtitle: entry.artist.name,
                        imageURL: entry.imageURL,
                        url: entry.url,
                        playcount: entry.playcount?.intValue,
                        track: entry
                    )
                }

            case .artists:
                let response = try await service.getTopArtists(period: period, limit: 50)
                guard let entry = response.entries.randomElement() else {
                    error = "No artists found for this period."
                    isLoading = false
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    result = RandomResult(
                        name: entry.name,
                        subtitle: nil,
                        imageURL: entry.imageURL,
                        url: entry.url,
                        playcount: entry.playcount?.intValue,
                        artist: entry
                    )
                }

            case .albums:
                let response = try await service.getTopAlbums(period: period, limit: 50)
                guard let entry = response.entries.randomElement() else {
                    error = "No albums found for this period."
                    isLoading = false
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    result = RandomResult(
                        name: entry.name,
                        subtitle: entry.artist?.name,
                        imageURL: entry.imageURL,
                        url: entry.url,
                        playcount: entry.playcount?.intValue,
                        album: entry
                    )
                }

            case .loved:
                let response = try await service.getLoves(limit: 50)
                guard let entry = response.entries.randomElement() else {
                    error = "No loved tracks found."
                    isLoading = false
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    result = RandomResult(
                        name: entry.name,
                        subtitle: entry.artist.name,
                        imageURL: entry.imageURL,
                        url: entry.url,
                        track: entry
                    )
                }
            }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}
