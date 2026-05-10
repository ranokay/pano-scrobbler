import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDragOver = false

    // Sidebar section grouping
    private let musicSections: [AppSection] = [.nowPlaying, .history, .charts, .friends, .profile, .search]
    private let toolSections: [AppSection] = [.random, .collage, .manualScrobble, .fileScrobble, .artworkSearch]
    private let manageSections: [AppSection] = [.accounts, .apps, .edits]
    private let systemSections: [AppSection] = [.settings, .logs]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .navigationTitle(model.selectedSection?.rawValue ?? "Pano Scrobbler")
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            Task { await model.reloadServices() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh all service connections")

                        Button {
                            Task { await model.retryPendingNow() }
                        } label: {
                            Label("Retry Pending", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("Retry all pending scrobbles")
                    }

                    ToolbarItemGroup {
                        Button {
                            model.importBundle()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            model.exportBundle()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.accentColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.commaSeparatedText, .json, .plainText, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $model.selectedSection) {
            Section("Music") {
                ForEach(musicSections) { section in
                    sidebarLabel(section)
                }
            }

            Section("Tools") {
                ForEach(toolSections) { section in
                    sidebarLabel(section)
                }
            }

            Section("Manage") {
                ForEach(manageSections) { section in
                    sidebarLabel(section)
                }
            }

            Section("System") {
                ForEach(systemSections) { section in
                    sidebarLabel(section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter(state: model.status.state)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
    }

    private func sidebarLabel(_ section: AppSection) -> some View {
        Label {
            HStack {
                Text(section.rawValue)
                Spacer()
                sidebarBadge(for: section)
            }
        } icon: {
            Image(systemName: section.filledSystemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .tag(section)
    }

    @ViewBuilder
    private func sidebarBadge(for section: AppSection) -> some View {
        switch section {
        case .nowPlaying:
            if model.pendingCount > 0 {
                StatusBadge(count: model.pendingCount, color: AccentColors.warning)
            }
        case .accounts:
            StatusBadge(
                count: model.accounts.filter(\.enabled).count,
                color: AccentColors.success
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch model.selectedSection {
        case .nowPlaying:
            NowPlayingView(model: model)
        case .history:
            ScrobbleHistoryView(model: model)
        case .charts:
            ChartsView(model: model)
        case .friends:
            FriendsView(model: model)
        case .profile:
            ProfileView(model: model)
        case .search:
            SearchView(model: model)
        case .random:
            RandomView(model: model)
        case .collage:
            CollageView(model: model)
        case .manualScrobble:
            ManualScrobbleView(model: model)
        case .fileScrobble:
            FileScrobbleView(model: model)
        case .artworkSearch:
            ImageSearchView(model: model)
        case .accounts:
            AccountsView(model: model)
        case .apps:
            AppsAllowlistView(model: model)
        case .edits:
            EditsBlocksView(model: model)
        case .settings:
            SettingsView(model: model)
        case .logs:
            LogsView(model: model)
        case nil:
            NowPlayingView(model: model)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    let ext = url.pathExtension.lowercased()
                    if ["csv", "json", "txt"].contains(ext) {
                        DispatchQueue.main.async {
                            model.selectedSection = .fileScrobble
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - Sidebar Footer

private struct SidebarFooter: View {
    var state: PlaybackState

    var body: some View {
        HStack(spacing: Spacing.sm) {
            PulsingDot(
                color: state.dotColor,
                size: 7,
                isPulsing: state == .playing
            )

            Text(state.displayLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - AppSection Extensions

extension AppSection {
    var filledSystemImage: String {
        switch self {
        case .nowPlaying: "music.note.list"
        case .history: "clock.arrow.circlepath"
        case .charts: "chart.bar.fill"
        case .friends: "person.2.fill"
        case .profile: "person.circle.fill"
        case .search: "magnifyingglass"
        case .random: "dice.fill"
        case .collage: "photo.artframe"
        case .manualScrobble: "pencil.line"
        case .fileScrobble: "doc.text.fill"
        case .artworkSearch: "photo.on.rectangle"
        case .accounts: "person.crop.circle.fill"
        case .apps: "app.badge.fill"
        case .edits: "slider.horizontal.3"
        case .settings: "gearshape.fill"
        case .logs: "doc.text.fill"
        }
    }
}
