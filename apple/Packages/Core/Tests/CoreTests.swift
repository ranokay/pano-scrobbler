import Testing
@testable import Core

@Test func firstArtistExtractionUsesCommonDelimiters() {
    #expect(FirstArtistExtractor.extract(from: "Artist feat. Guest") == "Artist")
    #expect(FirstArtistExtractor.extract(from: "Artist & Guest") == "Artist")
    #expect(FirstArtistExtractor.extract(from: "Solo Artist") == "Solo Artist")
}

@Test func timingUsesLastFmStyleMinimumDelay() {
    let prefs = ScrobbleTimingPreferences(delayPercent: 50, delaySeconds: 240, minimumDurationSeconds: 30)

    #expect(prefs.scrobbleDelay(duration: 180, alreadyPlayed: 0) == 90)
    #expect(prefs.scrobbleDelay(duration: 20, alreadyPlayed: 0) == 29.4)
    #expect(prefs.scrobbleDelay(duration: 180, alreadyPlayed: 89) == 2)
}

@Test func metadataPipelineAppliesBlocksBeforeEdits() {
    let data = ScrobbleData(artist: "Blocked", track: "Song")
    let pipeline = MetadataPipeline(
        simpleEdits: [
            SimpleEdit(matchArtist: "Blocked", matchTrack: "Song", replacementArtist: "Other")
        ],
        blockRules: [
            BlockRule(field: .artist, value: "Blocked", action: .ignore)
        ]
    )

    let result = pipeline.preprocess(data)

    #expect(result.blockedAction == .ignore)
    #expect(result.scrobbleData.artist == "Blocked")
}

@Test func engineRetriesPendingScrobblesAndClearsSuccessfulItems() async throws {
    let store = InMemoryPendingScrobbleStore()
    let data = ScrobbleData(artist: "Artist", track: "Track")
    let pending = PendingScrobble(data: data)
    try await store.enqueue(pending)

    let engine = ScrobbleEngine(
        services: [SuccessfulScrobbleService()],
        pendingStore: store
    )

    let summary = await engine.retryPending()

    #expect(summary == PendingRetrySummary(attempted: 1, succeeded: 1, failed: 0))
    #expect(try await store.load(limit: 10).isEmpty)
}

private struct SuccessfulScrobbleService: ScrobbleService {
    var account = UserAccount(type: .file, username: "test")

    func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }

    func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }
}
