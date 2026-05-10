import SwiftUI
import Core

struct ProfileView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                profileContent
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            if model.userProfile == nil {
                model.loadUserProfile()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Profile")
                .font(.displayLarge)

            Spacer()

            Button {
                model.loadUserProfile()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var profileContent: some View {
        if let user = model.userProfile {
            VStack(spacing: Spacing.xl) {
                // Profile card
                GlassCard(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.lg) {
                        avatarView(for: user)
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(user.realname?.isEmpty == false ? user.realname! : user.name)
                                .font(.system(size: 22, weight: .bold, design: .rounded))

                            if user.realname?.isEmpty == false {
                                Text(user.name)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            if let country = user.country, !country.isEmpty, country != "None" {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 10))
                                    Text(country)
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.secondary)
                            }

                            if let date = user.registered?.date {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 10))
                                    Text("Scrobbling since \(date, format: .dateTime.month(.wide).year())")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let url = user.url.flatMap({ URL(string: $0) }) {
                            Link(destination: url) {
                                Label("View on Last.fm", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: Spacing.md) {
                    StatCard(title: "Scrobbles", value: user.playcount?.intValue, icon: "music.note")
                    StatCard(title: "Artists", value: user.artistCount?.intValue, icon: "person.fill")
                    StatCard(title: "Tracks", value: user.trackCount?.intValue, icon: "waveform")
                }
            }
        } else {
            ContentUnavailableView(
                "No Profile",
                systemImage: "person.circle",
                description: Text("Add a Last.fm account to view your profile.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        }
    }

    @ViewBuilder
    private func avatarView(for user: LastFMUser) -> some View {
        if let url = user.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    var title: String
    var value: Int?
    var icon: String

    var body: some View {
        GlassCard(spacing: Spacing.md) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)

                if let value {
                    Text(formatNumber(value))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
