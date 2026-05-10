import SwiftUI
import Core
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Scrobbling") {
                Toggle("Enable scrobbling", isOn: $model.preferences.scrobblerEnabled)
                Toggle("Submit now playing before scrobbling", isOn: $model.preferences.timing.submitNowPlaying)
            }

            Section("Timing") {
                Stepper(
                    "Scrobble at \(model.preferences.timing.delayPercent)% of track",
                    value: $model.preferences.timing.delayPercent,
                    in: 10...100, step: 5
                )
                Stepper(
                    "Or after \(model.preferences.timing.delaySeconds) seconds",
                    value: $model.preferences.timing.delaySeconds,
                    in: 30...600, step: 15
                )
                Stepper(
                    "Ignore tracks shorter than \(model.preferences.timing.minimumDurationSeconds)s",
                    value: $model.preferences.timing.minimumDurationSeconds,
                    in: 10...120, step: 5
                )
            }

            Section("Notifications") {
                Toggle("Show notification on scrobble", isOn: $model.preferences.notifyOnScrobble)
                Toggle("Show notification on now playing", isOn: $model.preferences.notifyOnNowPlaying)
            }

            Section("Discord Rich Presence") {
                Toggle("Show currently playing track in Discord", isOn: Binding(
                    get: { model.discordEnabled },
                    set: { model.toggleDiscord($0) }
                ))

                if model.discordEnabled {
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(model.discordConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(model.discordConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 12))
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
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.paths.rootDirectory.path)
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.paths.rootDirectory.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                LabeledContent("SQLite database") {
                    Text(model.paths.databaseURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            Section("Data") {
                HStack(spacing: Spacing.md) {
                    Button {
                        model.importBundle()
                    } label: {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        model.exportBundle()
                    } label: {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("Support") {
                Button {
                    copyBugReport()
                } label: {
                    Label("Copy Bug Report Info", systemImage: "ant.fill")
                }

                Button {
                    if let url = URL(string: "https://github.com/kawaiiDango/pano-scrobbler") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub Repository", systemImage: "link")
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(appVersion)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(appBuild)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("macOS") {
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Accounts") {
                    Text("\(model.accounts.filter(\.enabled).count) active")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        Task { await model.resetPreferences() }
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.preferences) {
            Task { await model.savePreferences() }
        }
    }

    // MARK: - Helpers

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
        Discord RPC: \(model.discordEnabled ? (model.discordConnected ? "Connected" : "Enabled, not connected") : "Disabled")
        Pending: \(model.pendingCount)
        
        Recent Logs:
        \(model.logs.prefix(30).joined(separator: "\n"))
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}
