import Foundation
import Core

public final class AppleScriptNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 3) {
        self.pollInterval = max(0, pollInterval)
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let task = Task {
                var lastSnapshot: PlaybackSnapshot?

                while !Task.isCancelled {
                    if let snapshot = await pollSnapshot() {
                        if snapshot != lastSnapshot {
                            continuation.yield(.snapshot(snapshot))
                            lastSnapshot = snapshot
                        }
                    } else if lastSnapshot != nil {
                        let stoppedSnapshot = lastSnapshot!
                        continuation.yield(
                            .playbackChanged(sessionID: stoppedSnapshot.session.id, state: .stopped, position: nil)
                        )
                        lastSnapshot = nil
                    }

                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func pollSnapshot() async -> PlaybackSnapshot? {
        if let music = runAppleScript(Self.musicScript), let snapshot = parseOutput(music) {
            return snapshot
        }

        if let spotify = runAppleScript(Self.spotifyScript), let snapshot = parseOutput(spotify) {
            return snapshot
        }

        if let vox = runAppleScript(Self.voxScript), let snapshot = parseOutput(vox) {
            return snapshot
        }

        for browser in Self.browserDefinitions {
            if let browserOutput = runAppleScript(Self.browserScript(for: browser)),
               let snapshot = parseOutput(browserOutput)
            {
                return snapshot
            }
        }

        return nil
    }

    private func runAppleScript(_ script: [String], timeout: TimeInterval = 2) -> String? {
        guard !Task.isCancelled else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut || Task.isCancelled {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.nilIfEmpty
    }

    private func parseOutput(_ output: String) -> PlaybackSnapshot? {
        let fields = output.components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }

        let appName = fields[0]
        let appID = fields[1]
        let title = fields[2]
        let artist = fields[3]
        let album = fields[4].nilIfEmpty
        let duration = TimeInterval(fields[5])
        let position = TimeInterval(fields[6])
        let trackURL = fields.count > 7 ? URL(string: fields[7]) : nil
        let artworkURL = fields.count > 8 ? URL(string: fields[8]) : nil

        guard !title.isEmpty, !artist.isEmpty else {
            return nil
        }

        let session = MediaSession(id: appID, appID: appID, appName: appName)
        let metadata = PlaybackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL,
            trackURL: trackURL
        )

        return PlaybackSnapshot(session: session, metadata: metadata, state: .playing, position: position)
    }

    private static let musicScript = [
        "tell application \"System Events\" to set isRunning to (name of processes) contains \"Music\"",
        "if isRunning is false then return \"\"",
        "tell application \"Music\"",
        "if player state is not playing then return \"\"",
        "set t to current track",
        "set trackName to name of t as string",
        "set artistName to artist of t as string",
        "set albumName to album of t as string",
        "set durationValue to duration of t as string",
        "set positionValue to player position as string",
        "return \"Music\" & tab & \"com.apple.Music\" & tab & trackName & tab & artistName & tab & albumName & tab & durationValue & tab & positionValue",
        "end tell"
    ]

    private static let spotifyScript = [
        "tell application \"System Events\" to set isRunning to (name of processes) contains \"Spotify\"",
        "if isRunning is false then return \"\"",
        "tell application \"Spotify\"",
        "if player state is not playing then return \"\"",
        "set t to current track",
        "set trackName to name of t as string",
        "set artistName to artist of t as string",
        "set albumName to album of t as string",
        "set durationValue to (duration of t / 1000) as string",
        "set positionValue to player position as string",
        "set artworkValue to \"\"",
        "try",
        "set artworkValue to artwork url of t as string",
        "end try",
        "return \"Spotify\" & tab & \"com.spotify.client\" & tab & trackName & tab & artistName & tab & albumName & tab & durationValue & tab & positionValue & tab & \"\" & tab & artworkValue",
        "end tell"
    ]

    private static let voxScript = [
        "tell application \"System Events\" to set voxProcesses to (processes whose name is \"VOX\")",
        "if (count of voxProcesses) is 0 then return \"\"",
        "set bundleID to \"com.coppertino.Vox\"",
        "try",
        "tell application \"System Events\" to set bundleID to bundle identifier of item 1 of voxProcesses",
        "end try",
        "tell application \"VOX\"",
        "try",
        "if player state is not 1 then return \"\"",
        "set trackName to track as string",
        "set artistName to artist as string",
        "set albumName to \"\"",
        "try",
        "set albumName to album as string",
        "end try",
        "set durationValue to total time as string",
        "set positionValue to current time as string",
        "set trackURLValue to \"\"",
        "try",
        "set trackURLValue to trackUrl as string",
        "end try",
        "return \"VOX\" & tab & bundleID & tab & trackName & tab & artistName & tab & albumName & tab & durationValue & tab & positionValue & tab & trackURLValue",
        "on error",
        "return \"\"",
        "end try",
        "end tell"
    ]

    private struct BrowserDefinition {
        var appName: String
        var bundleID: String
        var isSafari: Bool = false
    }

    private static let browserDefinitions = [
        BrowserDefinition(appName: "Safari", bundleID: "com.apple.Safari", isSafari: true),
        BrowserDefinition(appName: "Google Chrome", bundleID: "com.google.Chrome"),
        BrowserDefinition(appName: "Brave Browser", bundleID: "com.brave.Browser"),
        BrowserDefinition(appName: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        BrowserDefinition(appName: "Arc", bundleID: "company.thebrowser.Browser"),
        BrowserDefinition(appName: "Chromium", bundleID: "org.chromium.Chromium"),
        BrowserDefinition(appName: "Vivaldi", bundleID: "com.vivaldi.Vivaldi")
    ]

    private static func browserScript(for browser: BrowserDefinition) -> [String] {
        let js = """
        (() => {
          const media = [...document.querySelectorAll('video,audio')].find((item) => !item.paused && !item.ended);
          const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
          if (!media || !metadata || !metadata.title || !metadata.artist) return '';
          const artwork = metadata.artwork && metadata.artwork.length ? metadata.artwork[metadata.artwork.length - 1].src : '';
          const duration = Number.isFinite(media.duration) ? String(media.duration) : '';
          const position = Number.isFinite(media.currentTime) ? String(media.currentTime) : '';
          return [metadata.title || '', metadata.artist || '', metadata.album || '', duration, position, location.href, artwork].join('\\t');
        })()
        """

        if browser.isSafari {
            return [
                "tell application \"System Events\" to set isRunning to (bundle identifier of processes) contains \"\(browser.bundleID)\"",
                "if isRunning is false then return \"\"",
                "tell application \"Safari\"",
                "repeat with w in windows",
                "repeat with t in tabs of w",
                "set tabURL to URL of t as string",
                "if tabURL starts with \"https://music.youtube.com\" or tabURL starts with \"http://music.youtube.com\" then",
                "try",
                "set resultText to do JavaScript \(js.quotedForAppleScript) in t",
                "if resultText is not \"\" then return \"\(browser.appName)\" & tab & \"\(browser.bundleID)\" & tab & resultText",
                "end try",
                "end if",
                "end repeat",
                "end repeat",
                "end tell",
                "return \"\""
            ]
        }

        return [
            "tell application \"System Events\" to set isRunning to (bundle identifier of processes) contains \"\(browser.bundleID)\"",
            "if isRunning is false then return \"\"",
            "tell application \"\(browser.appName)\"",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "set tabURL to URL of t as string",
            "if tabURL starts with \"https://music.youtube.com\" or tabURL starts with \"http://music.youtube.com\" then",
            "try",
            "set resultText to execute javascript \(js.quotedForAppleScript) in t",
            "if resultText is not \"\" then return \"\(browser.appName)\" & tab & \"\(browser.bundleID)\" & tab & resultText",
            "end try",
            "end if",
            "end repeat",
            "end repeat",
            "end tell",
            "return \"\""
        ]
    }
}

private extension String {
    var quotedForAppleScript: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }
}
