import Foundation
import Core

public enum LastFMPeriod: String, CaseIterable, Sendable {
    case week = "7day"
    case month = "1month"
    case quarter = "3month"
    case halfYear = "6month"
    case year = "12month"
    case overall = "overall"

    public var displayName: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last month"
        case .quarter: "Last 3 months"
        case .halfYear: "Last 6 months"
        case .year: "Last year"
        case .overall: "All time"
        }
    }
}

public struct LastFMService: ScrobbleService {
    public var account: UserAccount

    private let apiKey: String
    private let apiSecret: String
    private let sessionKey: String
    private let endpoint: URL
    private let httpClient: any HTTPClient

    public init(
        account: UserAccount,
        credentials: ServiceCredentials,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws {
        guard let apiKey = credentials.apiKey?.nilIfEmpty,
              let apiSecret = credentials.apiSecret?.nilIfEmpty,
              let sessionKey = credentials.sessionKey?.nilIfEmpty
        else {
            throw ScrobbleError.missingCredentials(account.type)
        }

        self.account = account
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.sessionKey = sessionKey
        self.endpoint = account.baseURL ?? URL(string: "https://ws.audioscrobbler.com/2.0/")!
        self.httpClient = httpClient
    }

    // MARK: - Write API

    public func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        var params = baseParams(method: "track.updateNowPlaying")
        params["artist"] = data.artist
        params["track"] = data.track
        params["album"] = data.album
        params["albumArtist"] = data.albumArtist
        try await callWrite(params: params)
        return ScrobbleResult()
    }

    public func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        var params = baseParams(method: "track.scrobble")
        params["artist"] = data.artist
        params["track"] = data.track
        params["album"] = data.album
        params["albumArtist"] = data.albumArtist
        params["timestamp"] = String(Int(data.timestamp.timeIntervalSince1970))
        try await callWrite(params: params)
        return ScrobbleResult()
    }

    public func scrobble(_ data: [ScrobbleData]) async throws -> ScrobbleResult {
        var params = baseParams(method: "track.scrobble")

        for (index, item) in data.enumerated() {
            params["artist[\(index)]"] = item.artist
            params["track[\(index)]"] = item.track
            params["timestamp[\(index)]"] = String(Int(item.timestamp.timeIntervalSince1970))
            params["album[\(index)]"] = item.album
            params["albumArtist[\(index)]"] = item.albumArtist
        }

        try await callWrite(params: params)
        return ScrobbleResult()
    }

    public func love(_ data: ScrobbleData) async throws -> ScrobbleResult {
        var params = baseParams(method: "track.love")
        params["artist"] = data.artist
        params["track"] = data.track
        try await callWrite(params: params)
        return ScrobbleResult()
    }

    public func unlove(_ data: ScrobbleData) async throws -> ScrobbleResult {
        var params = baseParams(method: "track.unlove")
        params["artist"] = data.artist
        params["track"] = data.track
        try await callWrite(params: params)
        return ScrobbleResult()
    }

    public func delete(_ data: ScrobbleData) async throws {
        var params = baseParams(method: "library.removeScrobble")
        params["artist"] = data.artist
        params["track"] = data.track
        params["timestamp"] = String(Int(data.timestamp.timeIntervalSince1970))
        try await callWrite(params: params)
    }

    // MARK: - Read API

    /// Fetch recent scrobbles for a user.
    public func getRecents(
        username: String? = nil,
        page: Int = 1,
        limit: Int = 50,
        from: Int? = nil,
        to: Int? = nil
    ) async throws -> PageResult<LastFMTrack> {
        var params: [String: String] = [
            "method": "user.getRecentTracks",
            "user": username ?? account.username,
            "page": String(page),
            "limit": String(limit),
            "extended": "1",
        ]
        if let from { params["from"] = String(from) }
        if let to { params["to"] = String(to) }

        let response: RecentTracksResponse = try await callRead(params: params)
        return PageResult(
            attr: response.recenttracks.attr?.toPageInfo() ?? PageInfo(),
            entries: response.recenttracks.track
        )
    }

    /// Fetch loved tracks for a user.
    public func getLoves(
        username: String? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PageResult<LastFMTrack> {
        let params: [String: String] = [
            "method": "user.getLovedTracks",
            "user": username ?? account.username,
            "page": String(page),
            "limit": String(limit),
        ]

        let response: LovedTracksResponse = try await callRead(params: params)
        return PageResult(
            attr: response.lovedtracks.attr?.toPageInfo() ?? PageInfo(),
            entries: response.lovedtracks.track
        )
    }

    /// Fetch user profile info.
    public func getUserInfo(username: String? = nil) async throws -> LastFMUser {
        let params: [String: String] = [
            "method": "user.getInfo",
            "user": username ?? account.username,
        ]

        let response: UserInfoResponse = try await callRead(params: params)
        return response.user
    }

    /// Fetch top artists for a user.
    public func getTopArtists(
        username: String? = nil,
        period: LastFMPeriod = .month,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PageResult<LastFMArtist> {
        let params: [String: String] = [
            "method": "user.getTopArtists",
            "user": username ?? account.username,
            "period": period.rawValue,
            "page": String(page),
            "limit": String(limit),
        ]

        let response: TopArtistsResponse = try await callRead(params: params)
        return PageResult(
            attr: response.topartists.attr?.toPageInfo() ?? PageInfo(),
            entries: response.topartists.artist
        )
    }

    /// Fetch top albums for a user.
    public func getTopAlbums(
        username: String? = nil,
        period: LastFMPeriod = .month,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PageResult<LastFMAlbum> {
        let params: [String: String] = [
            "method": "user.getTopAlbums",
            "user": username ?? account.username,
            "period": period.rawValue,
            "page": String(page),
            "limit": String(limit),
        ]

        let response: TopAlbumsResponse = try await callRead(params: params)
        return PageResult(
            attr: response.topalbums.attr?.toPageInfo() ?? PageInfo(),
            entries: response.topalbums.album
        )
    }

    /// Fetch top tracks for a user.
    public func getTopTracks(
        username: String? = nil,
        period: LastFMPeriod = .month,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PageResult<LastFMTrack> {
        let params: [String: String] = [
            "method": "user.getTopTracks",
            "user": username ?? account.username,
            "period": period.rawValue,
            "page": String(page),
            "limit": String(limit),
        ]

        let response: TopTracksResponse = try await callRead(params: params)
        return PageResult(
            attr: response.toptracks.attr?.toPageInfo() ?? PageInfo(),
            entries: response.toptracks.track
        )
    }

    /// Fetch friends for a user.
    public func getFriends(
        username: String? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> PageResult<LastFMUser> {
        let params: [String: String] = [
            "method": "user.getFriends",
            "user": username ?? account.username,
            "page": String(page),
            "limit": String(limit),
        ]

        let response: FriendsResponse = try await callRead(params: params)
        return PageResult(
            attr: response.friends.attr?.toPageInfo() ?? PageInfo(),
            entries: response.friends.user
        )
    }

    // MARK: - Info API

    /// Fetch detailed track info (play counts, tags, wiki, album info).
    public func getTrackInfo(
        artist: String,
        track: String,
        username: String? = nil
    ) async throws -> LastFMTrackInfo {
        var params: [String: String] = [
            "method": "track.getInfo",
            "artist": artist,
            "track": track,
        ]
        if let user = username ?? account.username.nilIfEmpty {
            params["username"] = user
        }

        let response: TrackInfoResponse = try await callRead(params: params)
        return response.track
    }

    /// Fetch detailed album info (tracks, tags, wiki).
    public func getAlbumInfo(
        artist: String,
        album: String,
        username: String? = nil
    ) async throws -> LastFMAlbumInfo {
        var params: [String: String] = [
            "method": "album.getInfo",
            "artist": artist,
            "album": album,
        ]
        if let user = username ?? account.username.nilIfEmpty {
            params["username"] = user
        }

        let response: AlbumInfoResponse = try await callRead(params: params)
        return response.album
    }

    /// Fetch detailed artist info (bio, similar, tags).
    public func getArtistInfo(
        artist: String,
        username: String? = nil
    ) async throws -> LastFMArtistInfo {
        var params: [String: String] = [
            "method": "artist.getInfo",
            "artist": artist,
        ]
        if let user = username ?? account.username.nilIfEmpty {
            params["username"] = user
        }

        let response: ArtistInfoResponse = try await callRead(params: params)
        return response.artist
    }

    /// Fetch similar tracks for a given track.
    public func getSimilarTracks(
        artist: String,
        track: String,
        limit: Int = 10
    ) async throws -> [LastFMSimilarTrack] {
        let params: [String: String] = [
            "method": "track.getSimilar",
            "artist": artist,
            "track": track,
            "limit": String(limit),
        ]

        let response: SimilarTracksResponse = try await callRead(params: params)
        return response.similartracks.track
    }

    /// Fetch similar artists for a given artist.
    public func getSimilarArtists(
        artist: String,
        limit: Int = 10
    ) async throws -> [LastFMArtist] {
        let params: [String: String] = [
            "method": "artist.getSimilar",
            "artist": artist,
            "limit": String(limit),
        ]

        let response: SimilarArtistsResponse = try await callRead(params: params)
        return response.similarartists.artist
    }

    /// Fetch top tracks for a given artist.
    public func getArtistTopTracks(
        artist: String,
        limit: Int = 10
    ) async throws -> [LastFMTrack] {
        let params: [String: String] = [
            "method": "artist.getTopTracks",
            "artist": artist,
            "limit": String(limit),
        ]

        let response: ArtistTopTracksResponse = try await callRead(params: params)
        return response.toptracks.track
    }

    /// Fetch top albums for a given artist.
    public func getArtistTopAlbums(
        artist: String,
        limit: Int = 10
    ) async throws -> [LastFMAlbum] {
        let params: [String: String] = [
            "method": "artist.getTopAlbums",
            "artist": artist,
            "limit": String(limit),
        ]

        let response: ArtistTopAlbumsResponse = try await callRead(params: params)
        return response.topalbums.album
    }

    // MARK: - Internal Helpers

    private func baseParams(method: String) -> [String: String] {
        [
            "method": method,
            "api_key": apiKey,
            "sk": sessionKey,
            "format": "json"
        ]
    }

    /// POST call for write operations (scrobble, love, etc.)
    private func callWrite(params input: [String: String]) async throws {
        var params = input.compactMapValues { $0.nilIfEmpty }
        params["api_sig"] = apiSignature(params)

        let response = try await httpClient.send(
            HTTPRequest(
                url: endpoint,
                method: "POST",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: FormEncoding.encode(params)
            )
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("Last.fm returned HTTP \(response.statusCode).")
        }

        if let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           let error = object["error"] {
            let message = object["message"] as? String ?? "Last.fm API error \(error)."
            throw ScrobbleError.invalidResponse(message)
        }
    }

    /// GET call for read operations — returns decoded JSON.
    private func callRead<T: Decodable>(params input: [String: String]) async throws -> T {
        var params = input
        params["api_key"] = apiKey
        params["format"] = "json"

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }

        let response = try await httpClient.send(
            HTTPRequest(
                url: components.url!,
                method: "GET",
                headers: [:],
                body: nil
            )
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("Last.fm returned HTTP \(response.statusCode).")
        }

        // Check for API error
        if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           let error = object["error"] {
            let message = object["message"] as? String ?? "Last.fm API error \(error)."
            throw ScrobbleError.invalidResponse(message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: response.data)
    }

    public func apiSignature(_ params: [String: String]) -> String {
        let source = params
            .filter { $0.key != "format" && $0.key != "callback" && $0.key != "api_sig" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined() + apiSecret

        return MD5.hash(source)
    }
}

// MARK: - Last.fm OAuth Authentication

/// Static helpers for the Last.fm token authentication flow.
/// Flow: getToken → open browser → poll getSession until authorized.
public enum LastFMAuth {

    private struct TokenResponse: Codable {
        var token: String
    }

    private struct SessionResponse: Codable {
        var session: SessionData

        struct SessionData: Codable {
            var name: String?
            var key: String
        }
    }

    /// Step 1: Get an auth token from Last.fm.
    public static func getToken(
        apiKey: String,
        apiSecret: String,
        endpoint: URL = URL(string: "https://ws.audioscrobbler.com/2.0/")!,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> String {
        var params: [String: String] = [
            "method": "auth.getToken",
            "api_key": apiKey,
            "format": "json"
        ]
        params["api_sig"] = signParams(params, secret: apiSecret)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }

        let response = try await httpClient.send(
            HTTPRequest(url: components.url!, method: "GET", headers: [:], body: nil)
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("Last.fm auth.getToken returned HTTP \(response.statusCode).")
        }

        let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: response.data)
        return tokenResp.token
    }

    /// Step 2: Build the URL the user should visit to authorize the token.
    public static func authorizationURL(apiKey: String, token: String) -> URL {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url!
    }

    /// Step 3: Exchange the authorized token for a session key.
    /// Returns (username, sessionKey) on success.
    public static func getSession(
        apiKey: String,
        apiSecret: String,
        token: String,
        endpoint: URL = URL(string: "https://ws.audioscrobbler.com/2.0/")!,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> (username: String, sessionKey: String) {
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token,
            "format": "json"
        ]
        params["api_sig"] = signParams(params, secret: apiSecret)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }

        let response = try await httpClient.send(
            HTTPRequest(url: components.url!, method: "GET", headers: [:], body: nil)
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("Last.fm auth.getSession returned HTTP \(response.statusCode).")
        }

        // Check for API error (code 14 = token not yet authorized)
        if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           let error = object["error"] as? Int {
            let message = object["message"] as? String ?? "Last.fm API error \(error)."
            throw ScrobbleError.authPending(code: error, message: message)
        }

        let session = try JSONDecoder().decode(SessionResponse.self, from: response.data)
        return (username: session.session.name ?? "unknown", sessionKey: session.session.key)
    }

    private static func signParams(_ params: [String: String], secret: String) -> String {
        let source = params
            .filter { $0.key != "format" && $0.key != "callback" && $0.key != "api_sig" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined() + secret

        return MD5.hash(source)
    }
}
