import Foundation
import Testing
import Core
@testable import Services

@Test func md5MatchesKnownVectors() {
    #expect(MD5.hash("") == "d41d8cd98f00b204e9800998ecf8427e")
    #expect(MD5.hash("abc") == "900150983cd24fb0d6963f7d28e17f72")
}

@Test func listenBrainzPayloadIncludesRequiredMetadata() throws {
    let data = ScrobbleData(artist: "Artist", track: "Track", album: "Album", timestamp: Date(timeIntervalSince1970: 42))
    let payload = try ListenBrainzService.makePayload(data, listenType: "single")
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])

    #expect(object["listen_type"] as? String == "single")
    let listens = try #require(object["payload"] as? [[String: Any]])
    #expect(listens.first?["listened_at"] as? Int == 42)
}

@Test func lastFMSignatureSortsParametersAndExcludesFormat() throws {
    let account = UserAccount(type: .lastFM, username: "user")
    let service = try LastFMService(
        account: account,
        credentials: ServiceCredentials(apiKey: "key", apiSecret: "secret", sessionKey: "session")
    )

    let signature = service.apiSignature([
        "format": "json",
        "track": "Track",
        "artist": "Artist",
        "method": "track.scrobble",
        "api_key": "key",
        "sk": "session"
    ])

    #expect(signature == MD5.hash("api_keykeyartistArtistmethodtrack.scrobblesksessiontrackTracksecret"))
}

@Test func listenBrainzFeedbackRequestsMsidAndPostsFeedback() async throws {
    let client = RecordingHTTPClient(responses: [
        HTTPResponse(statusCode: 200, data: #"{"recording_msid":"msid-1"}"#.data(using: .utf8)!),
        HTTPResponse(statusCode: 200, data: #"{}"#.data(using: .utf8)!)
    ])
    let service = try ListenBrainzService(
        account: UserAccount(type: .listenBrainz, username: "user"),
        credentials: ServiceCredentials(token: "token"),
        httpClient: client
    )

    _ = try await service.love(ScrobbleData(artist: "Artist", track: "Track"))
    let requests = await client.sentRequests

    #expect(requests.count == 2)
    #expect(URLComponents(url: requests[0].url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .contains(URLQueryItem(name: "return_msid", value: "true")) == true)
    #expect(requests[1].url.path.hasSuffix("/1/feedback/recording-feedback"))
}

@Test func listenBrainzFeedbackThrowsWhenMsidIsMissing() async throws {
    let client = RecordingHTTPClient(responses: [
        HTTPResponse(statusCode: 200, data: #"{}"#.data(using: .utf8)!)
    ])
    let service = try ListenBrainzService(
        account: UserAccount(type: .listenBrainz, username: "user"),
        credentials: ServiceCredentials(token: "token"),
        httpClient: client
    )

    do {
        _ = try await service.love(ScrobbleData(artist: "Artist", track: "Track"))
        Issue.record("Expected missing recording_msid to throw")
    } catch let error as ScrobbleError {
        #expect(!error.isAuthPending)
    }
}

@Test func lastFMAuthOnlyTreatsCode14AsPending() async throws {
    let client = RecordingHTTPClient(responses: [
        HTTPResponse(statusCode: 200, data: #"{"error":4,"message":"Invalid token"}"#.data(using: .utf8)!)
    ])

    do {
        _ = try await LastFMAuth.getSession(
            apiKey: "key",
            apiSecret: "secret",
            token: "token",
            httpClient: client
        )
        Issue.record("Expected terminal Last.fm auth error to throw")
    } catch let error as ScrobbleError {
        #expect(!error.isAuthPending)
        #expect(error.localizedDescription.contains("4"))
    }
}

@Test func lastFMSearchResponsesDecode() async throws {
    let client = RecordingHTTPClient(responses: [
        HTTPResponse(statusCode: 200, data: #"{"results":{"artistmatches":{"artist":[{"name":"Cher","url":"https://last.fm/music/Cher"}]}}}"#.data(using: .utf8)!),
        HTTPResponse(statusCode: 200, data: #"{"results":{"albummatches":{"album":[{"name":"Believe","artist":"Cher"}]}}}"#.data(using: .utf8)!),
        HTTPResponse(statusCode: 200, data: #"{"results":{"trackmatches":{"track":[{"name":"Believe","artist":"Cher"}]}}}"#.data(using: .utf8)!)
    ])
    let service = try LastFMService(
        account: UserAccount(type: .lastFM, username: "user"),
        credentials: ServiceCredentials(apiKey: "key", apiSecret: "secret", sessionKey: "session"),
        httpClient: client
    )

    let artists = try await service.searchArtists(query: "cher")
    let albums = try await service.searchAlbums(query: "believe")
    let tracks = try await service.searchTracks(query: "believe")

    #expect(artists.first?.name == "Cher")
    #expect(albums.first?.artist?.name == "Cher")
    #expect(tracks.first?.artist.name == "Cher")
}

@Test func updateCheckerPrefersDmgAssetURL() async {
    let client = RecordingHTTPClient(responses: [
        HTTPResponse(statusCode: 200, data: """
        {
          "tag_name": "macos-999",
          "name": "Release",
          "body": "Changes",
          "html_url": "https://github.com/example/repo/releases/tag/macos-999",
          "published_at": "2026-05-10T00:00:00Z",
          "assets": [
            {"name":"notes.txt","browser_download_url":"https://example.com/notes.txt","content_type":"text/plain"},
            {"name":"PanoScrobbler.dmg","browser_download_url":"https://example.com/PanoScrobbler.dmg","content_type":"application/x-apple-diskimage"}
          ]
        }
        """.data(using: .utf8)!)
    ])
    let checker = UpdateChecker(owner: "example", repo: "repo", httpClient: client)

    let update = await checker.checkForUpdate(currentVersion: "1")

    #expect(update?.downloadURL?.absoluteString == "https://example.com/PanoScrobbler.dmg")
}

private actor RecordingHTTPClient: HTTPClient {
    private var responses: [HTTPResponse]
    private(set) var sentRequests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        guard !responses.isEmpty else {
            throw ScrobbleError.invalidResponse("No mock response available.")
        }
        return responses.removeFirst()
    }
}
