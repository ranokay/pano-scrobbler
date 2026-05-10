import Foundation
import Testing
@testable import Core

@Test func firstArtistExtractionUsesCommonDelimiters() {
    #expect(FirstArtistExtractor.extract(from: "Artist feat. Guest") == "Artist")
    #expect(FirstArtistExtractor.extract(from: "Artist & Guest") == "Artist")
    #expect(FirstArtistExtractor.extract(from: "Solo Artist") == "Solo Artist")
}

@Test func timingUsesLastFmStyleMinimumDelay() {
    let prefs = ScrobbleTimingPreferences(delayPercent: 50, delaySeconds: 240, minimumDurationSeconds: 30)

    #expect(prefs.nextScrobbleDelay(duration: 180, alreadyPlayed: 0) == 90)
    #expect(prefs.nextScrobbleDelay(duration: 20, alreadyPlayed: 0) == nil)
    #expect(prefs.nextScrobbleDelay(duration: 180, alreadyPlayed: 89) == 1)
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

@Test func blockedAppIDsTakePrecedenceOverAllowedAppIDs() async {
    let accountID = UUID()
    let service = SuccessfulScrobbleService(account: UserAccount(id: accountID, type: .file, username: "test"))
    let presenter = RecordingNotificationPresenter()
    let engine = ScrobbleEngine(
        preferences: AppPreferences(
            allowedAppIDs: ["com.example.Player"],
            blockedAppIDs: ["com.example.Player"],
            notifyOnNowPlaying: true
        ),
        services: [service],
        notificationPresenter: presenter
    )

    await engine.handle(.snapshot(
        PlaybackSnapshot(
            session: MediaSession(id: "session", appID: "com.example.Player", appName: "Player"),
            metadata: PlaybackMetadata(title: "Track", artist: "Artist", duration: 180),
            state: .playing,
            position: 0
        )
    ))

    #expect(await engine.status() == NowPlayingStatus(state: .none))
    #expect(await presenter.notifications().isEmpty)
}

@Test func stoppedPlaybackCancelsStatusAndPendingScrobble() async throws {
    let recorder = ScrobbleRecorder()
    let service = RecordingScrobbleService(recorder: recorder)
    let engine = ScrobbleEngine(
        preferences: AppPreferences(
            timing: ScrobbleTimingPreferences(delayPercent: 50, delaySeconds: 240, minimumDurationSeconds: 1),
            notifyOnNowPlaying: true
        ),
        services: [service]
    )

    await engine.handle(.snapshot(
        PlaybackSnapshot(
            session: MediaSession(id: "session", appID: "com.example.Player", appName: "Player"),
            metadata: PlaybackMetadata(title: "Track", artist: "Artist", duration: 10),
            state: .playing,
            position: 4.9
        )
    ))
    await engine.handle(.playbackChanged(sessionID: "session", state: .stopped, position: nil))

    try await Task.sleep(nanoseconds: 250_000_000)

    #expect(await engine.status() == NowPlayingStatus(state: .stopped))
    #expect(await recorder.scrobbleCount() == 0)
}

@Test func shortTracksAreIgnoredForAutomaticScrobbling() async throws {
    let recorder = ScrobbleRecorder()
    let service = RecordingScrobbleService(recorder: recorder)
    let engine = ScrobbleEngine(
        preferences: AppPreferences(
            timing: ScrobbleTimingPreferences(delayPercent: 50, delaySeconds: 240, minimumDurationSeconds: 30),
            notifyOnNowPlaying: true
        ),
        services: [service]
    )

    await engine.handle(.snapshot(
        PlaybackSnapshot(
            session: MediaSession(id: "session", appID: "com.example.Player", appName: "Player"),
            metadata: PlaybackMetadata(title: "Short Track", artist: "Artist", duration: 12),
            state: .playing,
            position: 11
        )
    ))

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(await recorder.scrobbleCount() == 0)
}

@Test func manualScrobbleWithNoServicesDoesNotReportSuccess() async {
    let engine = ScrobbleEngine()
    let summary = await engine.scrobbleManually(ScrobbleData(artist: "Artist", track: "Track"))

    #expect(summary == "No services configured.")
}

@Test func partialServiceFailureRetriesOnlyFailedAccount() async throws {
    let store = InMemoryPendingScrobbleStore()
    let successfulAccount = UserAccount(id: UUID(), type: .lastFM, username: "ok")
    let failedAccount = UserAccount(id: UUID(), type: .listenBrainz, username: "fail")
    let data = ScrobbleData(artist: "Artist", track: "Track")

    let engine = ScrobbleEngine(
        services: [
            SuccessfulScrobbleService(account: successfulAccount),
            FailingScrobbleService(account: failedAccount)
        ],
        pendingStore: store
    )

    let manualSummary = await engine.scrobbleManually(data)
    let pending = try await store.load(limit: 10)

    #expect(manualSummary == "1 succeeded, 1 failed.")
    #expect(pending.count == 1)
    #expect(pending.first?.accountID == failedAccount.id)
    #expect(pending.first?.accountType == failedAccount.type)

    await engine.updateServices([SuccessfulScrobbleService(account: failedAccount)])
    let retrySummary = await engine.retryPending()

    #expect(retrySummary == PendingRetrySummary(attempted: 1, succeeded: 1, failed: 0))
    #expect(try await store.load(limit: 10).isEmpty)
}

@Test func targetedPendingScrobbleIsNotClearedWhenAccountIsMissing() async throws {
    let store = InMemoryPendingScrobbleStore()
    let missingAccount = UserAccount(id: UUID(), type: .lastFM, username: "missing")
    let pending = PendingScrobble(
        data: ScrobbleData(artist: "Artist", track: "Track"),
        accountID: missingAccount.id,
        accountType: missingAccount.type
    )
    try await store.enqueue(pending)

    let engine = ScrobbleEngine(
        services: [SuccessfulScrobbleService(account: UserAccount(type: .listenBrainz, username: "other"))],
        pendingStore: store
    )

    let retrySummary = await engine.retryPending()

    #expect(retrySummary == PendingRetrySummary(attempted: 1, succeeded: 0, failed: 1))
    #expect(try await store.load(limit: 10) == [pending])
}

@Test func retryPendingWithNoServicesDoesNotReportSuccess() async throws {
    let store = InMemoryPendingScrobbleStore()
    let pending = PendingScrobble(data: ScrobbleData(artist: "Artist", track: "Track"))
    try await store.enqueue(pending)

    let engine = ScrobbleEngine(pendingStore: store)
    let retrySummary = await engine.retryPending()

    #expect(retrySummary == PendingRetrySummary(attempted: 1, succeeded: 0, failed: 1))
    #expect(try await store.load(limit: 10) == [pending])
}

@Test func notificationPreferencesFilterNowPlayingAndScrobbledOnly() async {
    let presenter = RecordingNotificationPresenter()
    let engine = ScrobbleEngine(
        preferences: AppPreferences(notifyOnScrobble: false, notifyOnNowPlaying: false),
        services: [SuccessfulScrobbleService()],
        notificationPresenter: presenter
    )

    await engine.handle(.snapshot(
        PlaybackSnapshot(
            session: MediaSession(id: "session", appID: "com.example.Player", appName: "Player"),
            metadata: PlaybackMetadata(title: "Track", artist: "Artist", duration: 180),
            state: .playing,
            position: 0
        )
    ))
    _ = await engine.scrobbleManually(ScrobbleData(artist: "Artist", track: "Track"))

    #expect(await presenter.notifications().isEmpty)
}

private struct SuccessfulScrobbleService: ScrobbleService {
    var account = UserAccount(type: .file, username: "test")

    init(account: UserAccount = UserAccount(type: .file, username: "test")) {
        self.account = account
    }

    func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }

    func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }
}

private struct FailingScrobbleService: ScrobbleService {
    var account: UserAccount

    func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.invalidResponse("failed")
    }

    func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.invalidResponse("failed")
    }
}

private struct RecordingScrobbleService: ScrobbleService {
    var account = UserAccount(type: .file, username: "test")
    let recorder: ScrobbleRecorder

    func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }

    func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        await recorder.recordScrobble(data)
        return ScrobbleResult()
    }
}

private actor ScrobbleRecorder {
    private var scrobbles: [ScrobbleData] = []

    func recordScrobble(_ data: ScrobbleData) {
        scrobbles.append(data)
    }

    func scrobbleCount() -> Int {
        scrobbles.count
    }
}

private actor RecordingNotificationPresenter: NotificationPresenter {
    private var values: [ScrobbleNotification] = []

    func notify(_ notification: ScrobbleNotification) async {
        values.append(notification)
    }

    func notifications() -> [ScrobbleNotification] {
        values
    }
}
