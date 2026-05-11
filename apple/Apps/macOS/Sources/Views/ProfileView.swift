import Core
import SwiftUI

struct ProfileView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                if let user = model.userProfile {
                    hero(user: user)
                    statsGrid(user: user)
                } else {
                    ContentUnavailableView(
                        "No Profile",
                        systemImage: "person.circle",
                        description: Text("Add a Last.fm account to view your profile.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.loadUserProfile()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if model.userProfile == nil {
                model.loadUserProfile()
            }
        }
    }

    // MARK: - Hero

    private func hero(user: LastFMUser) -> some View {
        HStack(spacing: Layout.sectionSpacing) {
            avatarView(for: user)
                .frame(width: 80, height: 80)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(user.realname?.isEmpty == false ? user.realname! : user.name)
                    .font(.title.weight(.semibold))

                if user.realname?.isEmpty == false {
                    Text(user.name)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let country = user.country, !country.isEmpty, country != "None" {
                    Label(country, systemImage: "location.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                if let date = user.registered?.date {
                    Label("Scrobbling since \(date, format: .dateTime.month(.wide).year())",
                          systemImage: "calendar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let url = user.url.flatMap({ URL(string: $0) }) {
                Link(destination: url) {
                    Label("View on Last.fm", systemImage: "arrow.up.right.square")
                }
                .standardGlassButton()
            }
        }
        .heroGlass()
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
            .fill(.background.tertiary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Stats Grid

    private func statsGrid(user: LastFMUser) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: Layout.sectionSpacing) {
            StatCard(title: "Scrobbles", value: user.playcount?.intValue, icon: "music.note")
            StatCard(title: "Artists", value: user.artistCount?.intValue, icon: "person.fill")
            StatCard(title: "Tracks", value: user.trackCount?.intValue, icon: "waveform")
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    var title: String
    var value: Int?
    var icon: String

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let value {
                    Text(formatNumber(value))
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
