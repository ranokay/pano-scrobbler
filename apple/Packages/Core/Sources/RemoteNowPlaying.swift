import Foundation

/// A "now playing" track surfaced from a remote scrobbling service.
/// Used to display what the user is listening to on other devices.
public struct RemoteNowPlayingEntry: Identifiable, Equatable, Sendable {
    public enum Source: String, Sendable, Equatable {
        case lastFM
        case listenBrainz
    }

    public var id: String
    public var source: Source
    public var username: String
    public var artist: String
    public var track: String
    public var album: String?
    public var artworkURL: URL?
    /// Timestamp the remote service reported the track started (may be nil).
    public var since: Date?

    public init(
        id: String? = nil,
        source: Source,
        username: String,
        artist: String,
        track: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        since: Date? = nil
    ) {
        self.source = source
        self.username = username
        self.artist = artist
        self.track = track
        self.album = album
        self.artworkURL = artworkURL
        self.since = since
        self.id = id ?? "\(source.rawValue)|\(username)|\(artist)|\(track)"
    }

    public var sourceDisplayName: String {
        switch source {
        case .lastFM: "Last.fm"
        case .listenBrainz: "ListenBrainz"
        }
    }

    /// Matches a local ScrobbleData by artist + track (case-insensitive).
    public func matchesLocal(_ data: ScrobbleData) -> Bool {
        artist.caseInsensitiveCompare(data.artist) == .orderedSame
            && track.caseInsensitiveCompare(data.track) == .orderedSame
    }
}

// MARK: - URL helpers

public extension URL {
    /// True if this URL is the well-known Last.fm "no image" placeholder.
    /// Last.fm deprecated artist images in 2019 and serves a star image
    /// (path contains `2a96cbd8b46e442fc41c2b86b821562f`) for most artists
    /// and tracks without an album.
    var isLastFMPlaceholder: Bool {
        let s = absoluteString
        return s.contains("2a96cbd8b46e442fc41c2b86b821562f")
            || s.contains("c6f59c1e5e7240a4c0d427abd71f3dbb") // older placeholder hash
            || s.isEmpty
    }
}
