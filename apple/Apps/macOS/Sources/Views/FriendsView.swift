import Core
import SwiftUI

struct FriendsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isLoadingFriends && model.friends.isEmpty {
                ProgressView("Loading friends…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.friends.isEmpty {
                ContentUnavailableView(
                    "No Friends",
                    systemImage: "person.2.fill",
                    description: Text("Follow some users on Last.fm to see them here.")
                )
            } else {
                friendsList
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.loadFriends(page: 1)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingFriends)
            }
        }
        .onAppear {
            if model.friends.isEmpty {
                model.loadFriends()
            }
        }
    }

    private var subtitle: String {
        model.friendsPage.total > 0 ? "\(model.friendsPage.total.formatted()) friends" : ""
    }

    private var friendsList: some View {
        List {
            ForEach(model.friends, id: \.name) { friend in
                FriendRow(user: friend)
            }

            if model.friendsPage.page < model.friendsPage.totalPages {
                HStack {
                    Spacer()
                    Button {
                        model.loadFriends(page: model.friendsPage.page + 1)
                    } label: {
                        if model.isLoadingFriends {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load More")
                        }
                    }
                    .disabled(model.isLoadingFriends)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    var user: LastFMUser

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            avatarView
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.realname?.isEmpty == false ? user.realname! : user.name)
                    .font(.body)
                    .lineLimit(1)

                if user.realname?.isEmpty == false {
                    Text(user.name)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let plays = user.playcount?.intValue, plays > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatNumber(plays))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()

                    Text("scrobbles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let url = user.url.flatMap({ URL(string: $0) }) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
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
            .fill(.background.tertiary)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.tertiary)
            }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
