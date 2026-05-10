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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                tabPicker
                buttonRow
                appsList
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("App Filter")
                .font(.displayLarge)

            Text(headerDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerDescription: String {
        switch selectedTab {
        case .allowlist:
            "Only scrobble from these apps. Leave empty to scrobble from all detected apps."
        case .blocklist:
            "Never scrobble from these apps, even if they are detected."
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Filter Mode", selection: $selectedTab) {
            ForEach(AppFilterTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: Spacing.md) {
            Button {
                chooseApp()
            } label: {
                Label("Choose App…", systemImage: "folder")
            }

            Spacer()
        }
    }

    // MARK: - Apps List

    @ViewBuilder
    private var appsList: some View {
        let ids: [String] = currentIDs

        if ids.isEmpty {
            ContentUnavailableView(
                selectedTab == .allowlist ? "All Apps Allowed" : "No Apps Blocked",
                systemImage: selectedTab == .allowlist ? "app.badge.checkmark" : "nosign",
                description: Text("Choose an app above to add it to the \(selectedTab.rawValue.lowercased()).")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        } else {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, bundleID in
                    AppRow(
                        bundleID: bundleID,
                        onDelete: {
                            withAnimation {
                                switch selectedTab {
                                case .allowlist:
                                    model.removeAllowedAppIDs(at: IndexSet(integer: index))
                                case .blocklist:
                                    model.removeBlockedAppIDs(at: IndexSet(integer: index))
                                }
                            }
                        }
                    )
                }
            }
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
    var onDelete: () -> Void

    var body: some View {
        GlassCard(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                appIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appName)
                        .font(.system(size: 13, weight: .medium))
                    Text(bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }

    private var appName: String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: path),
           let name = bundle.infoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String {
            return name
        }
        return bundleID
    }
}
