import AppKit
import Foundation
import Core

@MainActor
public final class StatusItemController: NSObject {
    public var onOpen: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onLove: (() -> Void)?
    public var onSkip: (() -> Void)?

    private let statusItem: NSStatusItem
    private let appName: String
    private var currentStatus = NowPlayingStatus()

    public init(appName: String = "Pano Scrobbler") {
        self.appName = appName
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    public func update(status: NowPlayingStatus) {
        currentStatus = status

        if let button = statusItem.button {
            let iconName: String
            switch status.state {
            case .playing: iconName = "music.note.list"
            case .paused: iconName = "pause.circle"
            case .stopped, .none, .waiting: iconName = "music.note"
            }
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            button.imagePosition = .imageLeading

            if let data = status.data, status.state == .playing {
                button.title = "\(data.artist) — \(data.track)"
            } else {
                button.title = ""
            }

            button.toolTip = tooltip(for: status)
        }

        rebuildMenu()
    }

    private func configure() {
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openClicked)
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let data = currentStatus.data {
            // Track info
            let trackItem = NSMenuItem(title: "♫ \(data.track)", action: nil, keyEquivalent: "")
            trackItem.isEnabled = false
            menu.addItem(trackItem)

            let artistItem = NSMenuItem(title: "  \(data.artist)", action: nil, keyEquivalent: "")
            artistItem.isEnabled = false
            menu.addItem(artistItem)

            if let album = data.album, !album.isEmpty {
                let albumItem = NSMenuItem(title: "  \(album)", action: nil, keyEquivalent: "")
                albumItem.isEnabled = false
                menu.addItem(albumItem)
            }

            if let appName = data.appName, !appName.isEmpty {
                let appItem = NSMenuItem(title: "  via \(appName)", action: nil, keyEquivalent: "")
                appItem.isEnabled = false
                menu.addItem(appItem)
            }

            menu.addItem(.separator())

            // Actions
            let loveItem = NSMenuItem(title: "Love Track", action: #selector(loveClicked), keyEquivalent: "l")
            loveItem.target = self
            menu.addItem(loveItem)

            menu.addItem(.separator())
        } else {
            let idleItem = NSMenuItem(title: "No track playing", action: nil, keyEquivalent: "")
            idleItem.isEnabled = false
            menu.addItem(idleItem)
            menu.addItem(.separator())
        }

        let openItem = NSMenuItem(title: "Open \(appName)", action: #selector(openClicked), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func tooltip(for status: NowPlayingStatus) -> String {
        guard let data = status.data else {
            return "\(appName) — No track playing"
        }

        var lines = ["\(data.track)", data.artist]
        if let album = data.album, !album.isEmpty {
            lines.append(album)
        }
        return lines.joined(separator: "\n")
    }

    @objc private func openClicked() { onOpen?() }
    @objc private func settingsClicked() { onSettings?() }
    @objc private func quitClicked() { onQuit?() }
    @objc private func loveClicked() { onLove?() }
    @objc private func skipClicked() { onSkip?() }
}
