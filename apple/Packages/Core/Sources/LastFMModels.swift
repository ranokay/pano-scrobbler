import Foundation

// MARK: - Last.fm API Read Models

/// Page metadata from Last.fm `@attr` fields.
public struct PageInfo: Codable, Sendable {
    public var page: Int
    public var totalPages: Int
    public var total: Int

    public init(page: Int = 1, totalPages: Int = 1, total: Int = 0) {
        self.page = page
        self.totalPages = totalPages
        self.total = total
    }
}

/// A paginated result set.
public struct PageResult<T: Codable & Sendable>: Codable, Sendable {
    public var attr: PageInfo
    public var entries: [T]

    public init(attr: PageInfo = PageInfo(), entries: [T] = []) {
        self.attr = attr
        self.entries = entries
    }

    public var hasMorePages: Bool {
        attr.page < attr.totalPages
    }
}

// MARK: - Last.fm Image

public struct LastFMImage: Codable, Sendable {
    public var size: String
    public var url: String

    public init(size: String, url: String) {
        self.size = size
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case size
        case url = "#text"
    }
}

// MARK: - Artist

public struct LastFMArtist: Codable, Identifiable, Sendable {
    public var name: String
    public var url: String?
    public var playcount: StringOrInt?
    public var listeners: StringOrInt?
    public var userplaycount: StringOrInt?
    public var image: [LastFMImage]?

    public var id: String { name.lowercased() }

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }

    enum CodingKeys: String, CodingKey {
        case name, url, playcount, listeners, userplaycount, image
    }

    // Handle Last.fm returning artist as just a string "#text" in some contexts
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let name = try? container.decode(String.self) {
            self.name = name
            self.url = nil
            self.playcount = nil
            self.listeners = nil
            self.userplaycount = nil
            self.image = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Artist name can be in "name" or "#text"
        if let name = try? container.decode(String.self, forKey: .name) {
            self.name = name
        } else {
            let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)
            self.name = try altContainer.decode(String.self, forKey: .text)
        }
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.playcount = try container.decodeIfPresent(StringOrInt.self, forKey: .playcount)
        self.listeners = try container.decodeIfPresent(StringOrInt.self, forKey: .listeners)
        self.userplaycount = try container.decodeIfPresent(StringOrInt.self, forKey: .userplaycount)
        self.image = try container.decodeIfPresent([LastFMImage].self, forKey: .image)
    }

    private enum AltCodingKeys: String, CodingKey {
        case text = "#text"
    }

    public init(name: String, url: String? = nil) {
        self.name = name
        self.url = url
        self.playcount = nil
        self.listeners = nil
        self.userplaycount = nil
        self.image = nil
    }
}

// MARK: - Album

public struct LastFMAlbum: Codable, Identifiable, Sendable {
    public var name: String
    public var artist: LastFMArtist?
    public var url: String?
    public var playcount: StringOrInt?
    public var image: [LastFMImage]?

    public var id: String { "\(artist?.name ?? "")|\(name)".lowercased() }

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }

    enum CodingKeys: String, CodingKey {
        case name, artist, url, playcount, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Album name can be in "name" or "#text" or "title"
        if let name = try? container.decode(String.self, forKey: .name) {
            self.name = name
        } else {
            let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)
            self.name = try (altContainer.decodeIfPresent(String.self, forKey: .text))
                ?? (altContainer.decode(String.self, forKey: .title))
        }

        self.artist = try container.decodeIfPresent(LastFMArtist.self, forKey: .artist)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.playcount = try container.decodeIfPresent(StringOrInt.self, forKey: .playcount)
        self.image = try container.decodeIfPresent([LastFMImage].self, forKey: .image)
    }

    private enum AltCodingKeys: String, CodingKey {
        case text = "#text"
        case title
    }

    public init(name: String, artist: LastFMArtist? = nil) {
        self.name = name
        self.artist = artist
        self.url = nil
        self.playcount = nil
        self.image = nil
    }
}

// MARK: - Track (from getRecents / getLoves)

public struct LastFMTrack: Codable, Identifiable, Sendable {
    public var name: String
    public var artist: LastFMArtist
    public var album: LastFMAlbum?
    public var url: String?
    public var date: LastFMDate?
    public var image: [LastFMImage]?
    public var loved: StringOrBool?
    public var playcount: StringOrInt?
    public var attr: TrackAttr?

    public var id: String { "\(artist.name)|\(name)|\(date?.uts ?? "")".lowercased() }

    public var isNowPlaying: Bool {
        attr?.nowplaying?.boolValue ?? false
    }

    public var imageURL: URL? {
        let albumURL = album?.imageURL
        let trackURL = image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
        return trackURL ?? albumURL
    }

    public var timestamp: Date? {
        date?.uts.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case name, artist, album, url, date, image, loved, playcount
        case attr = "@attr"
    }

    public init(
        name: String,
        artist: LastFMArtist,
        album: LastFMAlbum? = nil,
        url: String? = nil,
        date: LastFMDate? = nil,
        image: [LastFMImage]? = nil,
        loved: StringOrBool? = nil,
        playcount: StringOrInt? = nil,
        attr: TrackAttr? = nil
    ) {
        self.name = name
        self.artist = artist
        self.album = album
        self.url = url
        self.date = date
        self.image = image
        self.loved = loved
        self.playcount = playcount
        self.attr = attr
    }
}

public struct TrackAttr: Codable, Hashable, Sendable {
    public var nowplaying: StringOrBool?
}

public struct LastFMDate: Codable, Hashable, Sendable {
    public var uts: String?

    enum CodingKeys: String, CodingKey {
        case uts
    }
}

// MARK: - User

public struct LastFMUser: Codable, Sendable {
    public var name: String
    public var url: String?
    public var realname: String?
    public var playcount: StringOrInt?
    public var artistCount: StringOrInt?
    public var trackCount: StringOrInt?
    public var albumCount: StringOrInt?
    public var image: [LastFMImage]?
    public var registered: LastFMRegistered?
    public var country: String?

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }

    enum CodingKeys: String, CodingKey {
        case name, url, realname, playcount, image, registered, country
        case artistCount = "artist_count"
        case trackCount = "track_count"
        case albumCount = "album_count"
    }
}

public struct LastFMRegistered: Codable, Sendable {
    public var unixtime: String?

    public var date: Date? {
        unixtime.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
    }
}

// MARK: - API Response Wrappers

public struct RecentTracksResponse: Codable, Sendable {
    public var recenttracks: RecentTracksContainer
}

public struct RecentTracksContainer: Codable, Sendable {
    public var track: [LastFMTrack]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case track
        case attr = "@attr"
    }
}

public struct LovedTracksResponse: Codable, Sendable {
    public var lovedtracks: LovedTracksContainer
}

public struct LovedTracksContainer: Codable, Sendable {
    public var track: [LastFMTrack]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case track
        case attr = "@attr"
    }
}

public struct UserInfoResponse: Codable, Sendable {
    public var user: LastFMUser
}

public struct TopArtistsResponse: Codable, Sendable {
    public var topartists: TopArtistsContainer
}

public struct TopArtistsContainer: Codable, Sendable {
    public var artist: [LastFMArtist]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case artist
        case attr = "@attr"
    }
}

public struct TopAlbumsResponse: Codable, Sendable {
    public var topalbums: TopAlbumsContainer
}

public struct TopAlbumsContainer: Codable, Sendable {
    public var album: [LastFMAlbum]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case album
        case attr = "@attr"
    }
}

public struct TopTracksResponse: Codable, Sendable {
    public var toptracks: TopTracksContainer
}

public struct TopTracksContainer: Codable, Sendable {
    public var track: [LastFMTrack]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case track
        case attr = "@attr"
    }
}

public struct FriendsResponse: Codable, Sendable {
    public var friends: FriendsContainer
}

public struct FriendsContainer: Codable, Sendable {
    public var user: [LastFMUser]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case user
        case attr = "@attr"
    }
}

public struct PageAttrResponse: Codable, Sendable {
    public var page: StringOrInt?
    public var totalPages: StringOrInt?
    public var total: StringOrInt?

    public func toPageInfo() -> PageInfo {
        PageInfo(
            page: page?.intValue ?? 1,
            totalPages: totalPages?.intValue ?? 1,
            total: total?.intValue ?? 0
        )
    }
}

// MARK: - String-or-Primitive Wrappers

/// Last.fm sometimes returns numbers as strings, sometimes as actual ints.
public enum StringOrInt: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)

    public var intValue: Int {
        switch self {
        case .string(let s): Int(s) ?? 0
        case .int(let i): i
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .int(0)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

/// Last.fm sometimes returns bools as strings ("true"/"1"/etc).
public enum StringOrBool: Codable, Hashable, Sendable {
    case string(String)
    case bool(Bool)

    public var boolValue: Bool {
        switch self {
        case .string(let s): s == "true" || s == "1"
        case .bool(let b): b
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .bool(false)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .bool(let b): try container.encode(b)
        }
    }
}

// MARK: - Tag

public struct LastFMTag: Codable, Identifiable, Sendable {
    public var name: String
    public var url: String?
    public var count: StringOrInt?

    public var id: String { name.lowercased() }
}

public struct LastFMWiki: Codable, Sendable {
    public var published: String?
    public var summary: String?
    public var content: String?
}

// MARK: - Track Info (track.getInfo response)

public struct TrackInfoResponse: Codable, Sendable {
    public var track: LastFMTrackInfo
}

public struct LastFMTrackInfo: Codable, Sendable {
    public var name: String
    public var url: String?
    public var duration: StringOrInt?
    public var listeners: StringOrInt?
    public var playcount: StringOrInt?
    public var userplaycount: StringOrInt?
    public var userloved: StringOrBool?
    public var artist: LastFMArtist?
    public var album: LastFMAlbum?
    public var toptags: LastFMTopTags?
    public var wiki: LastFMWiki?

    public var durationSeconds: Int {
        let ms = duration?.intValue ?? 0
        return ms > 0 ? ms / 1000 : 0
    }
}

// MARK: - Album Info (album.getInfo response)

public struct AlbumInfoResponse: Codable, Sendable {
    public var album: LastFMAlbumInfo
}

public struct LastFMAlbumInfo: Codable, Sendable {
    public var name: String
    public var artist: String?
    public var url: String?
    public var image: [LastFMImage]?
    public var listeners: StringOrInt?
    public var playcount: StringOrInt?
    public var userplaycount: StringOrInt?
    public var tracks: AlbumTracks?
    public var tags: LastFMTopTags?
    public var wiki: LastFMWiki?

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }
}

public struct AlbumTracks: Codable, Sendable {
    public var track: [AlbumTrackEntry]
}

public struct AlbumTrackEntry: Codable, Identifiable, Sendable {
    public var name: String
    public var url: String?
    public var duration: StringOrInt?
    public var rank: StringOrInt?
    public var artist: LastFMArtist?

    public var id: String { "\(rank?.intValue ?? 0)|\(name)" }

    enum CodingKeys: String, CodingKey {
        case name, url, duration, artist
        case rank = "@attr"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.duration = try container.decodeIfPresent(StringOrInt.self, forKey: .duration)
        self.artist = try container.decodeIfPresent(LastFMArtist.self, forKey: .artist)

        // @attr can be { "rank": "1" } or just a number
        if let attrObj = try? container.decode([String: StringOrInt].self, forKey: .rank) {
            self.rank = attrObj["rank"]
        } else {
            self.rank = try container.decodeIfPresent(StringOrInt.self, forKey: .rank)
        }
    }
}

// MARK: - Artist Info (artist.getInfo response)

public struct ArtistInfoResponse: Codable, Sendable {
    public var artist: LastFMArtistInfo
}

public struct LastFMArtistInfo: Codable, Sendable {
    public var name: String
    public var url: String?
    public var image: [LastFMImage]?
    public var listeners: StringOrInt?
    public var playcount: StringOrInt?
    public var userplaycount: StringOrInt?
    public var similar: SimilarArtists?
    public var tags: LastFMTopTags?
    public var bio: LastFMWiki?

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }
}

public struct SimilarArtists: Codable, Sendable {
    public var artist: [LastFMArtist]
}

// MARK: - Similar Tracks (track.getSimilar response)

public struct SimilarTracksResponse: Codable, Sendable {
    public var similartracks: SimilarTracksContainer
}

public struct SimilarTracksContainer: Codable, Sendable {
    public var track: [LastFMSimilarTrack]
}

public struct LastFMSimilarTrack: Codable, Identifiable, Sendable {
    public var name: String
    public var playcount: StringOrInt?
    public var match: Double?
    public var url: String?
    public var artist: LastFMArtist?
    public var image: [LastFMImage]?

    public var id: String { "\(artist?.name ?? "")|\\(name)".lowercased() }

    public var imageURL: URL? {
        image?.last(where: { !$0.url.isEmpty }).flatMap { URL(string: $0.url) }
    }
}

// MARK: - Similar Artists (artist.getSimilar response)

public struct SimilarArtistsResponse: Codable, Sendable {
    public var similarartists: SimilarArtistsContainer
}

public struct SimilarArtistsContainer: Codable, Sendable {
    public var artist: [LastFMArtist]
}

// MARK: - Artist Top Tracks (artist.getTopTracks response)

public struct ArtistTopTracksResponse: Codable, Sendable {
    public var toptracks: ArtistTopTracksContainer
}

public struct ArtistTopTracksContainer: Codable, Sendable {
    public var track: [LastFMTrack]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case track
        case attr = "@attr"
    }
}

// MARK: - Artist Top Albums (artist.getTopAlbums response)

public struct ArtistTopAlbumsResponse: Codable, Sendable {
    public var topalbums: ArtistTopAlbumsContainer
}

public struct ArtistTopAlbumsContainer: Codable, Sendable {
    public var album: [LastFMAlbum]
    public var attr: PageAttrResponse?

    enum CodingKeys: String, CodingKey {
        case album
        case attr = "@attr"
    }
}

// MARK: - Top Tags wrapper

public struct LastFMTopTags: Codable, Sendable {
    public var tag: [LastFMTag]
}
