import Foundation
import Core

enum AppConfiguration {
    static var displayName: String {
        string(for: "CFBundleDisplayName") ?? "Pano Scrobbler"
    }

    static var dataDirectoryName: String {
        string(for: "PanoAppDataDirectoryName") ?? "Pano Scrobbler"
    }

    static var keychainService: String {
        string(for: "PanoKeychainService") ?? "com.arn.scrobble.mac.credentials"
    }

    static var windowAutosaveName: String {
        string(for: "PanoWindowAutosaveName") ?? "PanoScrobblerMainWindow"
    }

    static var discordClientID: String? {
        string(for: "DiscordClientID")
    }

    private static func string(for key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}
