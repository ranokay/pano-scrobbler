import Foundation

struct AppPaths {
    var rootDirectory: URL

    var accountsURL: URL { rootDirectory.appendingPathComponent("accounts.json") }
    var preferencesURL: URL { rootDirectory.appendingPathComponent("preferences.json") }
    var rulesURL: URL { rootDirectory.appendingPathComponent("metadata-rules.json") }
    var databaseURL: URL { rootDirectory.appendingPathComponent("pano.sqlite") }
    var defaultFileScrobbleURL: URL { rootDirectory.appendingPathComponent("scrobbles.jsonl") }

    static var `default`: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(rootDirectory: base.appendingPathComponent(AppConfiguration.dataDirectoryName, isDirectory: true))
    }
}
