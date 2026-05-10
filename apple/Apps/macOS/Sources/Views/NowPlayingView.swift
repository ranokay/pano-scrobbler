import Core
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroCard
                metricsRow
                if model.status.data != nil {
                    trackDetails
                }
            }
            .padding(Spacing.lg)
        }
        .animation(.default, value: model.status.data?.stableIdentity)
    }

    // MARK: - Hero Card

    @ViewBuilder
    private var heroCard: some View {
        if let data = model.status.data {
            GlassCard(spacing: Spacing.lg) {
                HStack(spacing: Spacing.lg) {
                    artworkView(for: data)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(data.track)
                            .font(.displayLarge)
                            .lineLimit(2)
                            .contentTransition(.numericText())

                        Text(data.artist)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let album = data.album {
                            Text(album)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    AnimatedEqualizer(
                        isPlaying: model.status.state == .playing,
                        color: AccentColors.primary
                    )
                    .padding(.trailing, Spacing.sm)
                }
            }
            .transition(.blurReplace)
        } else {
            emptyState
        }
    }

    // MARK: - Artwork

    private func artworkView(for data: ScrobbleData) -> some View {
        Group {
            if let url = data.artworkURL {
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
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AccentColors.primary.opacity(0.6),
                    AccentColors.secondary.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GlassCard(spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AccentColors.primary.opacity(0.5))
                    .symbolEffect(.pulse, options: .repeating)

                Text("Listening for music…")
                    .font(.displaySmall)
                    .foregroundStyle(.secondary)

                Text("Play something in Music, Spotify, or any supported app.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        }
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: Spacing.md) {
            MetricCard(
                icon: "circle.fill",
                iconColor: model.status.state.dotColor,
                title: "State",
                value: model.status.state.displayLabel
            )

            MetricCard(
                icon: "person.2.fill",
                iconColor: AccentColors.primary,
                title: "Accounts",
                value: "\(model.accounts.filter(\.enabled).count)"
            )

            MetricCard(
                icon: "tray.full.fill",
                iconColor: model.pendingCount > 0 ? AccentColors.warning : .secondary,
                title: "Pending",
                value: "\(model.pendingCount)"
            )
        }
    }

    // MARK: - Track Details

    @ViewBuilder
    private var trackDetails: some View {
        if let data = model.status.data {
            GlassCard {
                Grid(alignment: .leading, horizontalSpacing: Spacing.lg, verticalSpacing: 12) {
                    DetailRow(label: "Album", value: data.album ?? "Unknown")
                    Divider()
                    DetailRow(label: "Album Artist", value: data.albumArtist ?? "Unknown")
                    Divider()
                    DetailRow(label: "App", value: data.appName ?? data.appID ?? "Unknown")
                    Divider()
                    DetailRow(label: "Started", value: data.timestamp.formatted(date: .omitted, time: .standard))
                    if let duration = data.duration {
                        Divider()
                        DetailRow(label: "Duration", value: formatDuration(duration))
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    var icon: String
    var iconColor: Color
    var title: String
    var value: String

    var body: some View {
        GlassCard(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.metricLabel)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text(value)
                    .font(.metricValue)
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    var label: String
    var value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
