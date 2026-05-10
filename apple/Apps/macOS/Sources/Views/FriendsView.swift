import SwiftUI
import Core

struct FriendsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                friendsList
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            if model.friends.isEmpty {
                model.loadFriends()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Friends")
                    .font(.displayLarge)

                if model.friendsPage.total > 0 {
                    Text("\(model.friendsPage.total) friend(s)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.loadFriends(page: 1)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingFriends)
        }
    }

    // MARK: - Friends List

    @ViewBuilder
    private var friendsList: some View {
        if model.isLoadingFriends && model.friends.isEmpty {
            ProgressView("Loading friends…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
        } else if model.friends.isEmpty {
            ContentUnavailableView(
                "No Friends",
                systemImage: "person.2.fill",
                description: Text("Follow some users on Last.fm to see them here.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        } else {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(model.friends, id: \.name) { friend in
                    FriendRow(user: friend)
                }

                if model.friendsPage.page < model.friendsPage.totalPages {
                    Button {
                        model.loadFriends(page: model.friendsPage.page + 1)
                    } label: {
                        if model.isLoadingFriends {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Load More")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .disabled(model.isLoadingFriends)
                }
            }
        }
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    var user: LastFMUser

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                avatarView
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.realname?.isEmpty == false ? user.realname! : user.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if user.realname?.isEmpty == false {
                        Text(user.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let plays = user.playcount?.intValue, plays > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatNumber(plays))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))

                        Text("scrobbles")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = user.url.flatMap({ URL(string: $0) }) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
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
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
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
