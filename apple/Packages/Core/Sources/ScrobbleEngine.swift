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
        guard !services.isEmpty else {
            return PendingRetrySummary()
        }

        let items: [PendingScrobble]
        do {
            items = try await pendingStore.load(limit: limit)
        } catch {
            return PendingRetrySummary()
        }

        var summary = PendingRetrySummary(attempted: items.count)

        for item in items {
            var errors: [String] = []

            for service in services where service.account.enabled {
                do {
                    _ = try await service.scrobble(item.data)
                } catch {
                    errors.append("\(service.account.type.displayName): \(error.localizedDescription)")
                }
            }

            if errors.isEmpty {
                try? await pendingStore.remove(id: item.id)
                summary.succeeded += 1
                await notificationPresenter.notify(.scrobbled(item.data))
            } else {
                let message = errors.joined(separator: "\n")
                try? await pendingStore.enqueue(
                    PendingScrobble(
                        id: item.id,
                        data: item.data,
                        event: item.event,
                        createdAt: item.createdAt,
                        lastError: message
                    )
                )
                summary.failed += 1
            }
        }

        return summary
    }

    public func handle(_ event: PlaybackEvent) async {
        guard preferences.scrobblerEnabled else { return }

        switch event {
        case let .sessionsChanged(mediaSessions):
            handleSessionsChanged(mediaSessions)
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
            await maybeScheduleScrobble(for: tracker)
        case let .snapshot(snapshot):
            var tracker = sessions[snapshot.session.id] ?? TrackSession(session: snapshot.session)
            tracker.session = snapshot.session
            tracker.metadata = snapshot.metadata
            tracker.state = snapshot.state
            tracker.position = snapshot.position
            sessions[snapshot.session.id] = tracker
            await maybeScheduleScrobble(for: tracker)
        }
    }

    private func handleSessionsChanged(_ mediaSessions: [MediaSession]) {
        let validIDs = Set(mediaSessions.map(\.id))

        for mediaSession in mediaSessions {
            if sessions[mediaSession.id] == nil {
                sessions[mediaSession.id] = TrackSession(session: mediaSession)
                Task { [notificationPresenter] in
                    await notificationPresenter.notify(
                        .appDetected(appID: mediaSession.appID, appName: mediaSession.appName)
                    )
                }
            }
        }

        for sessionID in sessions.keys where !validIDs.contains(sessionID) {
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

        let appIsAllowed = preferences.allowedAppIDs.isEmpty ||
            preferences.allowedAppIDs.contains(tracker.session.appID)

        guard appIsAllowed else {
            await notificationPresenter.notify(
                .appDetected(appID: tracker.session.appID, appName: tracker.session.appName)
            )
            return
        }

        let pipelineResult = pipeline.preprocess(rawData)
        let data = pipelineResult.scrobbleData
        let identity = data.stableIdentity

        if let blockedAction = pipelineResult.blockedAction {
            await notificationPresenter.notify(
                .blocked(data, pipelineResult.blockedReason ?? blockedAction.rawValue)
            )
            cancelTask(identity: identity)
            return
        }

        guard identity != sessions[tracker.session.id]?.lastIdentity else {
            return
        }

        sessions[tracker.session.id]?.lastIdentity = identity
        nowPlayingStatus = NowPlayingStatus(data: data, state: tracker.state)
        await notificationPresenter.notify(.nowPlaying(data))

        if preferences.timing.submitNowPlaying {
            submitNowPlaying(data)
        }

        let delay = preferences.timing.scrobbleDelay(
            duration: data.duration,
            alreadyPlayed: tracker.position
        )
        scheduleScrobble(data, identity: identity, delay: delay)
    }

    private func submitNowPlaying(_ data: ScrobbleData) {
        let services = services
        let notifications = notificationPresenter

        Task {
            for service in services where service.account.enabled {
                do {
                    _ = try await service.updateNowPlaying(data)
                } catch {
                    await notifications.notify(.failed(data, error.localizedDescription))
                }
            }
        }
    }

    private func scheduleScrobble(_ data: ScrobbleData, identity: String, delay: TimeInterval) {
        cancelTask(identity: identity)

        let services = services
        let pendingStore = pendingStore
        let notifications = notificationPresenter

        scrobbleTasks[identity] = Task {
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            var errors: [String] = []

            for service in services where service.account.enabled {
                do {
                    _ = try await service.scrobble(data)
                } catch {
                    errors.append("\(service.account.type.displayName): \(error.localizedDescription)")
                }
            }

            if errors.isEmpty {
                await notifications.notify(.scrobbled(data))
            } else {
                let message = errors.joined(separator: "\n")
                try? await pendingStore.enqueue(PendingScrobble(data: data, lastError: message))
                await notifications.notify(.failed(data, message))
            }
        }
    }

    /// Submit a manual scrobble directly to all active services (no delay/scheduling).
    public func scrobbleManually(_ data: ScrobbleData) async -> String {
        guard !services.isEmpty else {
            return "No services configured."
        }

        var succeeded = 0
        var errors: [String] = []

        for service in services where service.account.enabled {
            do {
                _ = try await service.scrobble(data)
                succeeded += 1
            } catch {
                errors.append("\(service.account.type.displayName): \(error.localizedDescription)")
            }
        }

        if errors.isEmpty {
            await notificationPresenter.notify(.scrobbled(data))
            return "\(succeeded) service(s) succeeded."
        } else {
            let message = errors.joined(separator: "\n")
            try? await pendingStore.enqueue(PendingScrobble(data: data, lastError: message))
            return "\(succeeded) succeeded, \(errors.count) failed."
        }
    }

    private func cancelTask(identity: String) {
        scrobbleTasks.removeValue(forKey: identity)?.cancel()
    }
}
