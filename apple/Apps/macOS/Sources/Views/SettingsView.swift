import AppKit
import Core
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Scrobbling") {
                Toggle("Enable scrobbling", isOn: $model.preferences.scrobblerEnabled)
                Toggle("Submit now playing before scrobbling",
                       isOn: $model.preferences.timing.submitNowPlaying)
            }

            Section("Timing") {
                Stepper(
                    "Scrobble at \(model.preferences.timing.delayPercent)% of track",
                    value: $model.preferences.timing.delayPercent,
                    in: 10...100,
                    step: 5
                )
                Stepper(
                    "Or after \(model.preferences.timing.delaySeconds) seconds",
                    value: $model.preferences.timing.delaySeconds,
                    in: 30...600,
                    step: 15
                )
                Stepper(
                    "Ignore tracks shorter than \(model.preferences.timing.minimumDurationSeconds) s",
                    value: $model.preferences.timing.minimumDurationSeconds,
                    in: 10...120,
                    step: 5
                )
            }

            Section("Notifications") {
                Toggle("Show notification on scrobble",
                       isOn: $model.preferences.notifyOnScrobble)
                Toggle("Show notification on now playing",
                       isOn: $model.preferences.notifyOnNowPlaying)
            }

            Section("Discord Rich Presence") {
                Toggle("Show currently playing track in Discord", isOn: Binding(
                    get: { model.discordEnabled },
                    set: { model.toggleDiscord($0) }
                ))
                .disabled(!model.discordAvailable)

                if !model.discordAvailable {
                    Text("Discord Rich Presence is disabled because this build does not include a Discord client ID.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if model.discordEnabled {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(model.discordConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(model.discordConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section("Storage") {
                LabeledContent("Data directory") {
                    Button {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: model.paths.rootDirectory.path
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.paths.rootDirectory.path)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.link)
                }

                LabeledContent("SQLite database") {
                    Text(model.paths.databaseURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("Data") {
                HStack {
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
                }
            }

            Section("Support") {
                HStack {
                    Button {
                        copyBugReport()
                    } label: {
                        Label("Copy Bug Report Info", systemImage: "ant")
                    }

                    Button {
                        if let url = URL(string: "https://github.com/kawaiiDango/pano-scrobbler") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("GitHub Repository", systemImage: "link")
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    metadataText(appVersion)
                }
                LabeledContent("Build") {
                    metadataText(appBuild)
                }
                LabeledContent("macOS") {
                    metadataText(ProcessInfo.processInfo.operatingSystemVersionString)
                }
                LabeledContent("Active accounts") {
                    Text("\(model.accounts.filter(\.enabled).count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    Task { await model.resetPreferences() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: model.preferences) {
            Task { await model.savePreferences() }
        }
    }

    // MARK: - Helpers

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private func copyBugReport() {
        let info = """
        Pano Scrobbler macOS Bug Report
        ===============================
        Version: \(appVersion) (\(appBuild))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accounts: \(model.accounts.map { "\($0.type.displayName): \($0.username)" }.joined(separator: ", "))
        Scrobbling: \(model.preferences.scrobblerEnabled ? "Enabled" : "Disabled")
        Discord RPC: \(model.discordAvailable ? (model.discordEnabled ? (model.discordConnected ? "Connected" : "Enabled, not connected") : "Disabled") : "Not configured")
        Pending: \(model.pendingCount)

        Recent Logs:
        \(model.logs.prefix(30).joined(separator: "\n"))
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}
