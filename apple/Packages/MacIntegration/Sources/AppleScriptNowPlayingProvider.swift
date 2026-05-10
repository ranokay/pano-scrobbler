import Foundation
import Core

public final class AppleScriptNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 3) {
        self.pollInterval = pollInterval
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
                    } else if let lastSnapshot {
                        continuation.yield(
                            .playbackChanged(sessionID: lastSnapshot.session.id, state: .stopped, position: nil)
                        )
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

        return nil
    }

    private func runAppleScript(_ script: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
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
        guard fields.count >= 6 else { return nil }

        let appName = fields[0]
        let title = fields[1]
        let artist = fields[2]
        let album = fields[3].nilIfEmpty
        let duration = TimeInterval(fields[4])
        let position = TimeInterval(fields[5])

        guard !title.isEmpty, !artist.isEmpty else {
            return nil
        }

        let appID = appName == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        let session = MediaSession(id: appID, appID: appID, appName: appName)
        let metadata = PlaybackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration
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
        "return \"Music\" & tab & trackName & tab & artistName & tab & albumName & tab & durationValue & tab & positionValue",
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
        "return \"Spotify\" & tab & trackName & tab & artistName & tab & albumName & tab & durationValue & tab & positionValue",
        "end tell"
    ]
}
