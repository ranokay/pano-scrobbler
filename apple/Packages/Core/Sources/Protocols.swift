import Foundation

public protocol ScrobbleService: Sendable {
    var account: UserAccount { get }

    func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult
    func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult
    func scrobble(_ data: [ScrobbleData]) async throws -> ScrobbleResult
    func love(_ data: ScrobbleData) async throws -> ScrobbleResult
    func unlove(_ data: ScrobbleData) async throws -> ScrobbleResult
    func delete(_ data: ScrobbleData) async throws
}

public extension ScrobbleService {
    func scrobble(_ data: [ScrobbleData]) async throws -> ScrobbleResult {
        for item in data {
            _ = try await scrobble(item)
        }
        return ScrobbleResult()
    }

    func love(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.notImplemented("Love is not implemented for \(account.type.displayName).")
    }

    func unlove(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.notImplemented("Unlove is not implemented for \(account.type.displayName).")
    }

    func delete(_ data: ScrobbleData) async throws {
        throw ScrobbleError.notImplemented("Delete is not implemented for \(account.type.displayName).")
    }
}

public protocol AccountStore: Sendable {
    func loadAccounts() async throws -> [UserAccount]
    func saveAccounts(_ accounts: [UserAccount]) async throws
}

public protocol SecretStore: Sendable {
    func loadCredentials(reference: String) async throws -> ServiceCredentials?
    func saveCredentials(_ credentials: ServiceCredentials, reference: String) async throws
    func deleteCredentials(reference: String) async throws
}

public protocol PendingScrobbleStore: Sendable {
    func enqueue(_ item: PendingScrobble) async throws
    func load(limit: Int) async throws -> [PendingScrobble]
    func remove(id: UUID) async throws
}

public protocol NowPlayingProvider: Sendable {
    func events() -> AsyncStream<PlaybackEvent>
}

public protocol PlayerCommandProvider: Sendable {
    func skip(sessionID: String) async throws
    func mute(sessionID: String) async throws
    func unmute(sessionID: String) async throws
}

public enum ScrobbleNotification: Sendable {
    case nowPlaying(ScrobbleData)
    case scrobbled(ScrobbleData)
    case failed(ScrobbleData, String)
    case blocked(ScrobbleData, String)
    case appDetected(appID: String, appName: String)
}

public protocol NotificationPresenter: Sendable {
    func notify(_ notification: ScrobbleNotification) async
}

public struct NoopNotificationPresenter: NotificationPresenter {
    public init() {}

    public func notify(_ notification: ScrobbleNotification) async {}
}

public actor InMemoryPendingScrobbleStore: PendingScrobbleStore {
    private var items: [PendingScrobble] = []

    public init() {}

    public func enqueue(_ item: PendingScrobble) async throws {
        items.append(item)
    }

    public func load(limit: Int) async throws -> [PendingScrobble] {
        Array(items.prefix(limit))
    }

    public func remove(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}
