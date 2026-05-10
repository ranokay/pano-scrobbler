import Foundation

public struct NowPlayingStatus: Equatable, Sendable {
    public var data: ScrobbleData?
    public var state: PlaybackState
    public var lastError: String?

    public init(data: ScrobbleData? = nil, state: PlaybackState = .none, lastError: String? = nil) {
        self.data = data
        self.state = state
        self.lastError = lastError
    }
}

public struct PendingRetrySummary: Equatable, Sendable {
    public var attempted: Int
    public var succeeded: Int
    public var failed: Int

    public init(attempted: Int = 0, succeeded: Int = 0, failed: Int = 0) {
        self.attempted = attempted
        self.succeeded = succeeded
        self.failed = failed
    }
}

private struct NotificationPolicy: Sendable {
    var notifyOnScrobble: Bool
    var notifyOnNowPlaying: Bool

    init(preferences: AppPreferences) {
        self.notifyOnScrobble = preferences.notifyOnScrobble
        self.notifyOnNowPlaying = preferences.notifyOnNowPlaying
    }

    func allows(_ notification: ScrobbleNotification) -> Bool {
        switch notification {
        case .nowPlaying:
            notifyOnNowPlaying
        case .scrobbled:
            notifyOnScrobble
        case .failed, .blocked, .appDetected:
            true
        }
    }
}

private struct TrackSession: Sendable {
    var session: MediaSession
    var metadata: PlaybackMetadata?
    var state: PlaybackState = .none
    var position: TimeInterval?
    var lastIdentity: String?

    var hasCompleteMetadata: Bool {
        guard let metadata else { return false }
        return !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !metadata.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func scrobbleData() -> ScrobbleData? {
        guard let metadata, hasCompleteMetadata else { return nil }
        return ScrobbleData(
            artist: metadata.artist,
            track: metadata.title,
            album: metadata.album,
            albumArtist: metadata.albumArtist,
            duration: metadata.duration,
            timestamp: Date().addingTimeInterval(-(position ?? 0)),
            appID: session.appID,
            appName: session.appName,
            trackURL: metadata.trackURL,
            artworkURL: metadata.artworkURL
        )
    }
}

public actor ScrobbleEngine {
    private var preferences: AppPreferences
    private var pipeline: MetadataPipeline
    private var services: [any ScrobbleService]
    private let pendingStore: any PendingScrobbleStore
    private let notificationPresenter: any NotificationPresenter
    private var sessions: [String: TrackSession] = [:]
    private var scrobbleTasks: [String: Task<Void, Never>] = [:]
    private var nowPlayingStatus = NowPlayingStatus()

    public init(
        preferences: AppPreferences = AppPreferences(),
        pipeline: MetadataPipeline = MetadataPipeline(),
        services: [any ScrobbleService] = [],
        pendingStore: any PendingScrobbleStore = InMemoryPendingScrobbleStore(),
        notificationPresenter: any NotificationPresenter = NoopNotificationPresenter()
    ) {
        self.preferences = preferences
        self.pipeline = pipeline
        self.services = services
        self.pendingStore = pendingStore
        self.notificationPresenter = notificationPresenter
    }

    deinit {
        for task in scrobbleTasks.values {
            task.cancel()
        }
    }

    public func updatePreferences(_ preferences: AppPreferences) {
        self.preferences = preferences
    }

    public func updatePipeline(_ pipeline: MetadataPipeline) {
        self.pipeline = pipeline
    }

    public func updateServices(_ services: [any ScrobbleService]) {
        self.services = services
    }

    public func status() -> NowPlayingStatus {
        nowPlayingStatus
    }

    public func run(provider: any NowPlayingProvider) async {
        for await event in provider.events() {
            await handle(event)
        }
    }

    public func retryPending(limit: Int = 50) async -> PendingRetrySummary {
        let items: [PendingScrobble]
        do {
            items = try await pendingStore.load(limit: limit)
        } catch {
            return PendingRetrySummary()
        }

        guard !services.isEmpty else {
            return PendingRetrySummary(attempted: items.count, succeeded: 0, failed: items.count)
        }

        var summary = PendingRetrySummary(attempted: items.count)

        for item in items {
            let targetServices = retryServices(for: item)
            guard !targetServices.isEmpty else {
                summary.failed += 1
                continue
            }

            let failedServices = await scrobble(item.data, services: targetServices)

            if failedServices.isEmpty {
                try? await pendingStore.remove(id: item.id)
                summary.succeeded += 1
                await notify(.scrobbled(item.data))
            } else {
                try? await pendingStore.remove(id: item.id)
                await enqueueFailures(failedServices, data: item.data, event: item.event, createdAt: item.createdAt)
                summary.failed += 1
            }
        }

        return summary
    }

    public func handle(_ event: PlaybackEvent) async {
        guard preferences.scrobblerEnabled else { return }

        switch event {
        case let .sessionsChanged(mediaSessions):
            await handleSessionsChanged(mediaSessions)
        case let .metadataChanged(sessionID, metadata):
            var tracker = sessions[sessionID]
            tracker?.metadata = metadata
            if let tracker {
                sessions[sessionID] = tracker
                await maybeScheduleScrobble(for: tracker)
            }
        case let .playbackChanged(sessionID, state, position):
            guard var tracker = sessions[sessionID] else { return }
            tracker.state = state
            tracker.position = position
            sessions[sessionID] = tracker
            if state == .playing {
                await maybeScheduleScrobble(for: tracker)
            } else {
                await handleInactivePlayback(for: sessionID, state: state)
            }
        case let .snapshot(snapshot):
            var tracker = sessions[snapshot.session.id] ?? TrackSession(session: snapshot.session)
            tracker.session = snapshot.session
            tracker.metadata = snapshot.metadata
            tracker.state = snapshot.state
            tracker.position = snapshot.position
            sessions[snapshot.session.id] = tracker
            if snapshot.state == .playing {
                await maybeScheduleScrobble(for: tracker)
            } else {
                await handleInactivePlayback(for: snapshot.session.id, state: snapshot.state)
            }
        }
    }

    private func handleSessionsChanged(_ mediaSessions: [MediaSession]) async {
        let validIDs = Set(mediaSessions.map(\.id))

        for mediaSession in mediaSessions {
            if sessions[mediaSession.id] == nil {
                sessions[mediaSession.id] = TrackSession(session: mediaSession)
                await notify(.appDetected(appID: mediaSession.appID, appName: mediaSession.appName))
            }
        }

        for sessionID in sessions.keys where !validIDs.contains(sessionID) {
            if let identity = sessions[sessionID]?.lastIdentity {
                cancelTask(identity: identity)
            }
            sessions.removeValue(forKey: sessionID)
        }
    }

    private func maybeScheduleScrobble(for tracker: TrackSession) async {
        guard tracker.state == .playing,
              tracker.hasCompleteMetadata,
              let rawData = tracker.scrobbleData()
        else {
            return
        }

        let rawIdentity = rawData.stableIdentity

        guard preferences.shouldScrobble(appID: tracker.session.appID) else {
            cancelPreviousIdentity(sessionID: tracker.session.id, replacementIdentity: nil)
            sessions[tracker.session.id]?.lastIdentity = nil
            nowPlayingStatus = NowPlayingStatus(state: .none)
            if !preferences.blockedAppIDs.contains(tracker.session.appID) {
                await notify(.appDetected(appID: tracker.session.appID, appName: tracker.session.appName))
            }
            return
        }

        let pipelineResult = pipeline.preprocess(rawData)
        let data = pipelineResult.scrobbleData
        let identity = data.stableIdentity

        if let blockedAction = pipelineResult.blockedAction {
            cancelPreviousIdentity(sessionID: tracker.session.id, replacementIdentity: rawIdentity)
            await notify(.blocked(data, pipelineResult.blockedReason ?? blockedAction.rawValue))
            cancelTask(identity: identity)
            sessions[tracker.session.id]?.lastIdentity = nil
            nowPlayingStatus = NowPlayingStatus(state: .none)
            return
        }

        guard identity != sessions[tracker.session.id]?.lastIdentity else {
            return
        }

        cancelPreviousIdentity(sessionID: tracker.session.id, replacementIdentity: identity)
        sessions[tracker.session.id]?.lastIdentity = identity
        nowPlayingStatus = NowPlayingStatus(data: data, state: tracker.state)
        await notify(.nowPlaying(data))

        if preferences.timing.submitNowPlaying {
            submitNowPlaying(data)
        }

        guard let delay = preferences.timing.nextScrobbleDelay(duration: data.duration, alreadyPlayed: tracker.position) else {
            cancelTask(identity: identity)
            return
        }

        scheduleScrobble(data, identity: identity, delay: delay)
    }

    private func submitNowPlaying(_ data: ScrobbleData) {
        Task { [weak self] in
            await self?.submitNowPlayingNow(data)
        }
    }

    private func scheduleScrobble(_ data: ScrobbleData, identity: String, delay: TimeInterval) {
        cancelTask(identity: identity)

        scrobbleTasks[identity] = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.submitScheduledScrobble(data, identity: identity)
        }
    }

    private func submitNowPlayingNow(_ data: ScrobbleData) async {
        for service in activeServices() {
            do {
                _ = try await service.updateNowPlaying(data)
            } catch {
                await notify(.failed(data, error.localizedDescription))
            }
        }
    }

    private func submitScheduledScrobble(_ data: ScrobbleData, identity: String) async {
        defer {
            scrobbleTasks.removeValue(forKey: identity)
        }

        let active = activeServices()
        guard !active.isEmpty else {
            await notify(.failed(data, "No services configured."))
            return
        }

        let failedServices = await scrobble(data, services: active)
        if failedServices.isEmpty {
            await notify(.scrobbled(data))
        } else {
            await enqueueFailures(failedServices, data: data)
            await notify(.failed(data, failedServices.map(\.message).joined(separator: "\n")))
        }
    }

    /// Submit a manual scrobble directly to all active services (no delay/scheduling).
    public func scrobbleManually(_ data: ScrobbleData) async -> String {
        let active = activeServices()
        guard !active.isEmpty else {
            return "No services configured."
        }

        let failedServices = await scrobble(data, services: active)
        let succeeded = active.count - failedServices.count

        if failedServices.isEmpty {
            await notify(.scrobbled(data))
            return "\(succeeded) service(s) succeeded."
        } else {
            await enqueueFailures(failedServices, data: data)
            return "\(succeeded) succeeded, \(failedServices.count) failed."
        }
    }

    private func handleInactivePlayback(for sessionID: String, state: PlaybackState) async {
        guard var tracker = sessions[sessionID] else {
            nowPlayingStatus = NowPlayingStatus(state: state)
            return
        }

        if let identity = tracker.lastIdentity {
            cancelTask(identity: identity)
        }
        tracker.lastIdentity = nil
        sessions[sessionID] = tracker

        if state == .paused, let data = tracker.scrobbleData() {
            nowPlayingStatus = NowPlayingStatus(data: pipeline.preprocess(data).scrobbleData, state: state)
        } else {
            nowPlayingStatus = NowPlayingStatus(state: state)
        }
    }

    private func activeServices() -> [any ScrobbleService] {
        services.filter(\.account.enabled)
    }

    private func retryServices(for item: PendingScrobble) -> [any ScrobbleService] {
        activeServices().filter { service in
            if let accountID = item.accountID {
                return service.account.id == accountID
            }
            if let accountType = item.accountType {
                return service.account.type == accountType
            }
            return true
        }
    }

    private struct ServiceFailure: Sendable {
        var account: UserAccount
        var message: String
    }

    private func scrobble(_ data: ScrobbleData, services: [any ScrobbleService]) async -> [ServiceFailure] {
        var failures: [ServiceFailure] = []

        for service in services {
            do {
                _ = try await service.scrobble(data)
            } catch {
                failures.append(
                    ServiceFailure(
                        account: service.account,
                        message: "\(service.account.type.displayName): \(error.localizedDescription)"
                    )
                )
            }
        }

        return failures
    }

    private func enqueueFailures(
        _ failures: [ServiceFailure],
        data: ScrobbleData,
        event: String = "scrobble",
        createdAt: Date = Date()
    ) async {
        for failure in failures {
            try? await pendingStore.enqueue(
                PendingScrobble(
                    data: data,
                    event: event,
                    createdAt: createdAt,
                    accountID: failure.account.id,
                    accountType: failure.account.type,
                    lastError: failure.message
                )
            )
        }
    }

    private func notify(_ notification: ScrobbleNotification) async {
        let policy = NotificationPolicy(preferences: preferences)
        guard policy.allows(notification) else { return }
        await notificationPresenter.notify(notification)
    }

    private func cancelPreviousIdentity(sessionID: String, replacementIdentity: String?) {
        guard let previous = sessions[sessionID]?.lastIdentity, previous != replacementIdentity else {
            return
        }
        cancelTask(identity: previous)
    }

    private func cancelTask(identity: String) {
        scrobbleTasks.removeValue(forKey: identity)?.cancel()
    }
}
