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
                    ToolbarItem(placement: .status) {
                        statusPill
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                Task { await model.reloadServices() }
                            } label: {
                                Label("Refresh Services", systemImage: "arrow.clockwise")
                            }
                            .help("Re-initialize service connections")

                            Button {
                                Task { await model.retryPendingNow() }
                            } label: {
                                Label("Retry Pending Scrobbles", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Divider()

                            Button {
                                model.importBundle()
                            } label: {
                                Label("Import Settings…", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                model.exportBundle()
                            } label: {
                                Label("Export Settings…", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
        .artworkCache(model.artworkCache)
        .adaptiveWindowBackground()
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    @ViewBuilder
    private func sidebarLabel(_ section: AppSection) -> some View {
        Label(section.rawValue, systemImage: section.systemImage)
            .symbolRenderingMode(.hierarchical)
            .badge(sidebarBadgeCount(for: section))
            .tag(section)
    }

    private func sidebarBadgeCount(for section: AppSection) -> Int {
        switch section {
        case .nowPlaying:
            return model.pendingCount
        case .accounts:
            return model.accounts.filter(\.enabled).count
        default:
            return 0
        }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: 6) {
            PulsingDot(
                color: model.presentationStatus.state.indicatorColor,
                size: 7,
                isPulsing: model.presentationStatus.state == .playing
            )

            Text(model.presentationStatus.state.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .interactiveGlass(cornerRadius: 100)
        .help("Scrobble engine status")
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
