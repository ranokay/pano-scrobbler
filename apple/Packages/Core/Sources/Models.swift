import Foundation

public enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case lastFM
    case libreFM
    case gnuFM
    case listenBrainz
    case customListenBrainz
    case pleroma
    case file

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lastFM: "Last.fm"
        case .libreFM: "Libre.fm"
        case .gnuFM: "GNU FM"
        case .listenBrainz: "ListenBrainz"
        case .customListenBrainz: "Custom ListenBrainz"
        case .pleroma: "Pleroma"
        case .file: "Local file"
        }
    }
}

public struct UserAccount: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var type: AccountType
    public var username: String
    public var baseURL: URL?
    public var credentialReference: String
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        type: AccountType,
        username: String,
        baseURL: URL? = nil,
        credentialReference: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.username = username
        self.baseURL = baseURL
        self.credentialReference = credentialReference ?? id.uuidString
        self.enabled = enabled
    }
}

public struct ServiceCredentials: Codable, Equatable, Sendable {
    public var apiKey: String?
    public var apiSecret: String?
    public var sessionKey: String?
    public var token: String?
    public var fileURL: URL?

    public init(
        apiKey: String? = nil,
        apiSecret: String? = nil,
        sessionKey: String? = nil,
        token: String? = nil,
        fileURL: URL? = nil
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.sessionKey = sessionKey
        self.token = token
        self.fileURL = fileURL
    }
}

public struct ScrobbleData: Codable, Hashable, Sendable {
    public var artist: String
    public var track: String
    public var album: String?
    public var albumArtist: String?
    public var duration: TimeInterval?
    public var timestamp: Date
    public var appID: String?
    public var appName: String?
    public var trackURL: URL?
    public var artworkURL: URL?
    public var musicBrainzID: String?

    public init(
        artist: String,
        track: String,
        album: String? = nil,
        albumArtist: String? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date = Date(),
        appID: String? = nil,
        appName: String? = nil,
        trackURL: URL? = nil,
        artworkURL: URL? = nil,
        musicBrainzID: String? = nil
    ) {
        self.artist = artist
        self.track = track
        self.album = album
        self.albumArtist = albumArtist
        self.duration = duration
        self.timestamp = timestamp
        self.appID = appID
        self.appName = appName
        self.trackURL = trackURL
        self.artworkURL = artworkURL
        self.musicBrainzID = musicBrainzID
    }

    public var stableIdentity: String {
        [
            appID ?? "",
            artist.lowercased(),
            track.lowercased(),
            album?.lowercased() ?? "",
            albumArtist?.lowercased() ?? ""
        ].joined(separator: "\u{1f}")
    }

    public func trimmed() -> ScrobbleData {
        ScrobbleData(
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            track: track.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            albumArtist: albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            duration: duration,
            timestamp: timestamp,
            appID: appID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            appName: appName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            trackURL: trackURL,
            artworkURL: artworkURL,
            musicBrainzID: musicBrainzID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

public struct ScrobbleResult: Codable, Equatable, Sendable {
    public var ignored: Bool
    public var serviceMessageID: String?

    public init(ignored: Bool = false, serviceMessageID: String? = nil) {
        self.ignored = ignored
        self.serviceMessageID = serviceMessageID
    }
}

public enum PlaybackState: String, Codable, Sendable {
    case none
    case playing
    case paused
    case stopped
    case waiting
}

public struct MediaSession: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var appID: String
    public var appName: String

    public init(id: String, appID: String, appName: String) {
        self.id = id
        self.appID = appID
        self.appName = appName
    }
}

public struct PlaybackMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    public var albumArtist: String?
    public var duration: TimeInterval?
    public var artworkURL: URL?
    public var trackURL: URL?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        albumArtist: String? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        trackURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.duration = duration
        self.artworkURL = artworkURL
        self.trackURL = trackURL
    }
}

public struct PlaybackSnapshot: Codable, Hashable, Sendable {
    public var session: MediaSession
    public var metadata: PlaybackMetadata
    public var state: PlaybackState
    public var position: TimeInterval?
    public var capturedAt: Date

    public init(
        session: MediaSession,
        metadata: PlaybackMetadata,
        state: PlaybackState,
        position: TimeInterval? = nil,
        capturedAt: Date = Date()
    ) {
        self.session = session
        self.metadata = metadata
        self.state = state
        self.position = position
        self.capturedAt = capturedAt
    }
}

public enum PlaybackEvent: Sendable {
    case sessionsChanged([MediaSession])
    case metadataChanged(sessionID: String, metadata: PlaybackMetadata)
    case playbackChanged(sessionID: String, state: PlaybackState, position: TimeInterval?)
    case snapshot(PlaybackSnapshot)
}

public struct ScrobbleTimingPreferences: Codable, Equatable, Sendable {
    public var delayPercent: Int
    public var delaySeconds: Int
    public var minimumDurationSeconds: Int
    public var submitNowPlaying: Bool

    public init(
        delayPercent: Int = 50,
        delaySeconds: Int = 240,
        minimumDurationSeconds: Int = 30,
        submitNowPlaying: Bool = true
    ) {
        self.delayPercent = delayPercent
        self.delaySeconds = delaySeconds
        self.minimumDurationSeconds = minimumDurationSeconds
        self.submitNowPlaying = submitNowPlaying
    }

    public func scrobbleDelay(duration: TimeInterval?, alreadyPlayed: TimeInterval?) -> TimeInterval {
        let durationSeconds = duration.map { max($0, 0) } ?? 120
        let fractionDelay = durationSeconds * Double(delayPercent) / 100
        let absoluteDelay = Double(delaySeconds)
        let minimumDelay = max(Double(minimumDurationSeconds) - 0.6, 2)
        let targetDelay = max(min(fractionDelay, absoluteDelay), minimumDelay)
        return max(targetDelay - (alreadyPlayed ?? 0), 2)
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var scrobblerEnabled: Bool
    public var allowedAppIDs: Set<String>
    public var blockedAppIDs: Set<String>
    public var timing: ScrobbleTimingPreferences
    public var activeAccountType: AccountType
    public var notifyOnScrobble: Bool
    public var notifyOnNowPlaying: Bool

    public init(
        scrobblerEnabled: Bool = true,
        allowedAppIDs: Set<String> = [],
        blockedAppIDs: Set<String> = [],
        timing: ScrobbleTimingPreferences = ScrobbleTimingPreferences(),
        activeAccountType: AccountType = .lastFM,
        notifyOnScrobble: Bool = true,
        notifyOnNowPlaying: Bool = false
    ) {
        self.scrobblerEnabled = scrobblerEnabled
        self.allowedAppIDs = allowedAppIDs
        self.blockedAppIDs = blockedAppIDs
        self.timing = timing
        self.activeAccountType = activeAccountType
        self.notifyOnScrobble = notifyOnScrobble
        self.notifyOnNowPlaying = notifyOnNowPlaying
    }

    /// Returns true if the given app ID is allowed to scrobble.
    public func shouldScrobble(appID: String) -> Bool {
        if blockedAppIDs.contains(appID) { return false }
        if allowedAppIDs.isEmpty { return true }
        return allowedAppIDs.contains(appID)
    }
}

public struct PendingScrobble: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var data: ScrobbleData
    public var event: String
    public var createdAt: Date
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        data: ScrobbleData,
        event: String = "scrobble",
        createdAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.id = id
        self.data = data
        self.event = event
        self.createdAt = createdAt
        self.lastError = lastError
    }
}

public enum ScrobbleError: LocalizedError, Sendable {
    case missingCredentials(AccountType)
    case unsupportedService(AccountType)
    case invalidResponse(String)
    case notImplemented(String)
    case authPending(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .missingCredentials(type): "Missing credentials for \(type.displayName)."
        case let .unsupportedService(type): "Unsupported service: \(type.displayName)."
        case let .invalidResponse(message): message
        case let .notImplemented(message): message
        case let .authPending(_, message): message
        }
    }

    /// Returns true if this is a "token not yet authorized" error (Last.fm code 14).
    public var isAuthPending: Bool {
        if case .authPending(let code, _) = self, code == 14 { return true }
        return false
    }
}

extension String {
    public var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
