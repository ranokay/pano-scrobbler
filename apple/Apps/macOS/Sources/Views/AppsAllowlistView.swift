import AppKit
import SwiftUI

struct AppsAllowlistView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: AppFilterTab = .allowlist

    enum AppFilterTab: String, CaseIterable {
        case allowlist = "Allowlist"
        case blocklist = "Blocklist"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter Mode", selection: $selectedTab) {
                ForEach(AppFilterTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Layout.windowPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: 360)

            Divider()

            content
        }
        .navigationSubtitle(headerDescription)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseApp()
                } label: {
                    Label("Choose App…", systemImage: "plus")
                }
            }
        }
    }

    private var headerDescription: String {
        switch selectedTab {
        case .allowlist:
            "Only scrobble from chosen apps (empty = all)"
        case .blocklist:
            "Never scrobble from chosen apps"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let ids = currentIDs

        if ids.isEmpty {
            ContentUnavailableView {
                Label(
                    selectedTab == .allowlist ? "All Apps Allowed" : "No Apps Blocked",
                    systemImage: selectedTab == .allowlist ? "app.badge.checkmark" : "nosign"
                )
            } description: {
                Text("Choose an app to add it to the \(selectedTab.rawValue.lowercased()).")
            } actions: {
                Button("Choose App…") {
                    chooseApp()
                }
            }
        } else {
            List {
                ForEach(Array(ids.enumerated()), id: \.element) { index, bundleID in
                    AppRow(bundleID: bundleID)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    switch selectedTab {
                                    case .allowlist:
                                        model.removeAllowedAppIDs(at: IndexSet(integer: index))
                                    case .blocklist:
                                        model.removeBlockedAppIDs(at: IndexSet(integer: index))
                                    }
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var currentIDs: [String] {
        switch selectedTab {
        case .allowlist: model.preferences.allowedAppIDs.sorted()
        case .blocklist: model.preferences.blockedAppIDs.sorted()
        }
    }

    // MARK: - App Picker

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                switch selectedTab {
                case .allowlist:
                    model.addAllowedAppID(id)
                case .blocklist:
                    model.addBlockedAppID(id)
                }
            }
        }
    }
}

// MARK: - App Row

private struct AppRow: View {
    var bundleID: String

    var body: some View {
        HStack(spacing: Layout.sectionSpacing) {
            appIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(appName).font(.body)
                Text(bundleID)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var appName: String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: path),
           let name = bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
        {
            return name
        }
        return bundleID
    }
}
