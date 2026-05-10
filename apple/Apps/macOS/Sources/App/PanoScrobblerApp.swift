import SwiftUI

@main
struct PanoScrobblerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup("Pano Scrobbler") {
            Group {
                if hasCompletedOnboarding {
                    ContentView(model: model)
                        .frame(minWidth: 1150, minHeight: 600)
                } else {
                    OnboardingView(model: model, hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .background(WindowStateTracker())
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            // App commands
            CommandGroup(after: .appInfo) {
                Button("Refresh Accounts") {
                    Task { await model.reloadServices() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // Navigation shortcuts
            CommandMenu("Navigate") {
                Button("Now Playing") {
                    model.selectedSection = .nowPlaying
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("History") {
                    model.selectedSection = .history
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Charts") {
                    model.selectedSection = .charts
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Friends") {
                    model.selectedSection = .friends
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Profile") {
                    model.selectedSection = .profile
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Search") {
                    model.selectedSection = .search
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Random") {
                    model.selectedSection = .random
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Collage") {
                    model.selectedSection = .collage
                }
                .keyboardShortcut("7", modifiers: .command)

                Button("Manual Scrobble") {
                    model.selectedSection = .manualScrobble
                }
                .keyboardShortcut("8", modifiers: .command)
            }

            // Scrobble commands
            CommandMenu("Scrobble") {
                Button("Retry Pending") {
                    Task { await model.retryPendingNow() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Import Settings…") {
                    model.importBundle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Export Settings…") {
                    model.exportBundle()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

/// Uses NSWindow's built-in frame autosave to persist window position/size.
private struct WindowStateTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName("PanoScrobblerMainWindow")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
