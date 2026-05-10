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
