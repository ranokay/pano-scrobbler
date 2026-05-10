import SwiftUI
import Core
import Services

/// Picks a random entry from the user's library — analogous to Kotlin RandomScreen.
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
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                controls
                resultView
            }
            .padding(Spacing.lg)
        }
        .sheet(item: $selectedTrack) { track in
            MusicEntryInfoView(model: model, track: track, album: nil, artist: nil)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Random")
                .font(.displayLarge)
            Text("Discover a random entry from your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            // Type picker
            Picker("Type", selection: $selectedType) {
                ForEach(RandomType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Period (hidden for loved)
            if selectedType != .loved {
                Picker("Period", selection: $period) {
                    ForEach(LastFMPeriod.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .frame(width: 150)
            }

            // Roll button
            Button {
                Task { await loadRandom() }
            } label: {
                Label("Roll", systemImage: "dice.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultView: some View {
        if isLoading {
            VStack(spacing: Spacing.md) {
                Spacer(minLength: 40)
                ProgressView()
                    .controlSize(.large)
                Text("Finding something…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        } else if let error {
            ContentUnavailableView(
                "No Result",
                systemImage: "dice",
                description: Text(error)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else if let result {
            GlassCard(spacing: Spacing.lg) {
                VStack(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.lg) {
                        // Artwork
                        AsyncImage(url: result.imageURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            default:
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 160, height: 160)
                                    .overlay {
                                        Image(systemName: selectedType.icon)
                                            .font(.system(size: 40))
                                            .foregroundStyle(.tertiary)
                                    }
                            }
                        }
                        .frame(width: 160, height: 160)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                        VStack(alignment: .leading, spacing: Spacing.sm) {
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
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 12))
                                    Text("\(pc) plays")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            HStack(spacing: Spacing.sm) {
                                if let track = result.track {
                                    Button {
                                        selectedTrack = track
                                    } label: {
                                        Label("Info", systemImage: "info.circle")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if let urlStr = result.url, let url = URL(string: urlStr) {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("Open", systemImage: "safari")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Button {
                                    Task { await loadRandom() }
                                } label: {
                                    Label("Next", systemImage: "forward.fill")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .opacity
            ))
        } else {
            VStack(spacing: Spacing.md) {
                Spacer(minLength: 60)
                Image(systemName: "dice")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
                Text("Press Roll to discover something from your library")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 60)
            }
            .frame(maxWidth: .infinity)
        }
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
