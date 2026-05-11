import Foundation
import Core

public struct ListenBrainzService: ScrobbleService {
    public var account: UserAccount

    private let token: String
    private let apiRoot: URL
    private let httpClient: any HTTPClient

    public init(
        account: UserAccount,
        credentials: ServiceCredentials,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws {
        guard let token = credentials.token?.nilIfEmpty else {
            throw ScrobbleError.missingCredentials(account.type)
        }

        self.account = account
        self.token = token
        self.apiRoot = account.baseURL ?? URL(string: "https://api.listenbrainz.org")!
        self.httpClient = httpClient
    }

    // MARK: - Write Operations

    public func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        try await submit(data, listenType: "playing_now")
        return ScrobbleResult()
    }

    public func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        try await submit(data, listenType: "single")
        return ScrobbleResult()
    }

    public func love(_ data: ScrobbleData) async throws -> ScrobbleResult {
        try await sendFeedback(artist: data.artist, track: data.track, score: 1)
        return ScrobbleResult()
    }

    public func unlove(_ data: ScrobbleData) async throws -> ScrobbleResult {
        try await sendFeedback(artist: data.artist, track: data.track, score: 0)
        return ScrobbleResult()
    }

    public func delete(_ data: ScrobbleData) async throws {
        // ListenBrainz delete requires recording_msid — not supported from ScrobbleData alone
        throw ScrobbleError.notImplemented("Delete requires recording_msid for ListenBrainz.")
    }

    // MARK: - Read Operations

    /// Get the currently-playing track(s) for a user.
    public func getPlayingNow(username: String? = nil) async throws -> [LBListen] {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/user/\(user)/playing-now")
        let data = try await get(url)
        let response = try JSONDecoder().decode(LBPlayingNowResponse.self, from: data)
        return response.payload.listens
    }

    /// Get recent listens for a user.
    public func getRecents(username: String? = nil, limit: Int = 25) async throws -> LBListensResponse {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/user/\(user)/listens")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "count", value: String(limit))
        ]

        let data = try await get(components.url!)
        return try JSONDecoder().decode(LBListensResponse.self, from: data)
    }

    /// Get loved tracks (feedback with score > 0) for a user.
    public func getLoves(username: String? = nil, limit: Int = 25, offset: Int = 0) async throws -> LBFeedbacksResponse {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/feedback/user/\(user)/get-feedback")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "metadata", value: "true"),
            URLQueryItem(name: "score", value: "1")
        ]

        let data = try await get(components.url!)
        return try JSONDecoder().decode(LBFeedbacksResponse.self, from: data)
    }

    /// Get users being followed by a user.
    public func getFollowing(username: String? = nil) async throws -> LBFollowingResponse {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/user/\(user)/following")
        let data = try await get(url)
        return try JSONDecoder().decode(LBFollowingResponse.self, from: data)
    }

    /// Get total listen count for a user.
    public func getListenCount(username: String? = nil) async throws -> Int {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/user/\(user)/listen-count")
        let data = try await get(url)
        let response = try JSONDecoder().decode(LBListenCountResponse.self, from: data)
        return response.payload.count
    }

    /// Get top charts (artists/releases/recordings) for a user.
    public func getCharts(type: LBChartType, range: LBRange = .all_time, username: String? = nil, limit: Int = 25, offset: Int = 0) async throws -> LBStatsResponse {
        let user = username ?? account.username
        let url = apiRoot.appendingPathComponent("1/stats/user/\(user)/\(type.rawValue)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "range", value: range.rawValue)
        ]

        let data = try await get(components.url!)
        return try JSONDecoder().decode(LBStatsResponse.self, from: data)
    }

    /// Validate a token.
    public static func validateToken(_ token: String, apiRoot: URL? = nil) async throws -> LBValidateTokenResponse {
        let root = apiRoot ?? URL(string: "https://api.listenbrainz.org")!
        let url = root.appendingPathComponent("1/validate-token")
        let client = URLSessionHTTPClient()

        let response = try await client.send(HTTPRequest(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Token \(token)",
                "Content-Type": "application/json"
            ],
            body: nil
        ))

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("ListenBrainz returned HTTP \(response.statusCode).")
        }

        return try JSONDecoder().decode(LBValidateTokenResponse.self, from: response.data)
    }

    // MARK: - Private Helpers

    private func submit(_ data: ScrobbleData, listenType: String) async throws {
        let body = try Self.makePayload(data, listenType: listenType)
        let url = apiRoot.appendingPathComponent("1/submit-listens")
        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: "POST",
                headers: [
                    "Authorization": "Token \(token)",
                    "Content-Type": "application/json"
                ],
                body: body
            )
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("ListenBrainz returned HTTP \(response.statusCode).")
        }
    }

    private func get(_ url: URL) async throws -> Data {
        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: "GET",
                headers: [
                    "Authorization": "Token \(token)",
                    "Content-Type": "application/json"
                ],
                body: nil
            )
        )

        guard 200..<300 ~= response.statusCode else {
            throw ScrobbleError.invalidResponse("ListenBrainz returned HTTP \(response.statusCode).")
        }

        return response.data
    }

    private func sendFeedback(artist: String, track: String, score: Int) async throws {
        // Send a now-playing first to get a recording_msid, then submit feedback
        // Try direct feedback — requires mbid (not always available)
        // For simplicity, submit now-playing first to get msid
        let npData = ScrobbleData(artist: artist, track: track, timestamp: Date())
        let npBody = try Self.makePayload(npData, listenType: "playing_now")
        let npURL = apiRoot.appendingPathComponent("1/submit-listens")

        let npResponse = try await httpClient.send(
            HTTPRequest(
                url: npURL,
                method: "POST",
                headers: [
                    "Authorization": "Token \(token)",
                    "Content-Type": "application/json"
                ],
                body: npBody
            )
        )

        // Parse the msid from the response
        if 200..<300 ~= npResponse.statusCode,
           let json = try? JSONSerialization.jsonObject(with: npResponse.data) as? [String: Any],
           let msid = json["recording_msid"] as? String {
            // Submit feedback with msid
            let feedbackBody = try JSONSerialization.data(
                withJSONObject: ["recording_msid": msid, "score": score],
                options: .sortedKeys
            )

            let fbURL = apiRoot.appendingPathComponent("1/feedback/recording-feedback")
            let fbResponse = try await httpClient.send(
                HTTPRequest(
                    url: fbURL,
                    method: "POST",
                    headers: [
                        "Authorization": "Token \(token)",
                        "Content-Type": "application/json"
                    ],
                    body: feedbackBody
                )
            )

            guard 200..<300 ~= fbResponse.statusCode else {
                throw ScrobbleError.invalidResponse("ListenBrainz feedback returned HTTP \(fbResponse.statusCode).")
            }
        }
    }

    public static func makePayload(_ data: ScrobbleData, listenType: String) throws -> Data {
        var metadata: [String: Any] = [
            "artist_name": data.artist,
            "track_name": data.track
        ]

        if let album = data.album?.nilIfEmpty {
            metadata["release_name"] = album
        }

        if let musicBrainzID = data.musicBrainzID?.nilIfEmpty {
            metadata["additional_info"] = ["recording_mbid": musicBrainzID]
        }

        var listen: [String: Any] = [
            "track_metadata": metadata
        ]

        if listenType != "playing_now" {
            listen["listened_at"] = Int(data.timestamp.timeIntervalSince1970)
        }

        let payload: [String: Any] = [
            "listen_type": listenType,
            "payload": [listen]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

// MARK: - ListenBrainz Enums

public enum LBChartType: String, CaseIterable, Sendable {
    case artists
    case releases
    case recordings
}

public enum LBRange: String, CaseIterable, Sendable {
    case this_week
    case this_month
    case this_year
    case week
    case month
    case quarter
    case half_yearly
    case year
    case all_time

    public var displayName: String {
        switch self {
        case .this_week: "This week"
        case .this_month: "This month"
        case .this_year: "This year"
        case .week: "Last week"
        case .month: "Last month"
        case .quarter: "Last quarter"
        case .half_yearly: "Last 6 months"
        case .year: "Last year"
        case .all_time: "All time"
        }
    }
}
