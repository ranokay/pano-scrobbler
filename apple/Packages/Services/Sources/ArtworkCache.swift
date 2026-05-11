import Core
import Foundation

/// Resolves artwork URLs for artists, albums, and tracks. When a hint URL is
/// known-bad (missing, empty, or the Last.fm placeholder), falls back to
/// iTunes and Deezer searches via `ArtworkLookupService`.
///
/// All lookups are cached in-memory for the app's lifetime. Misses are also
/// cached with a short TTL so failed lookups don't repeat every render.
public actor ArtworkCache {
    public enum Subject: Hashable, Sendable {
        case artist(name: String)
        case album(artist: String, name: String)
        case track(artist: String, title: String)

        var query: String {
            switch self {
            case .artist(let name):
                return name
            case .album(let artist, let name):
                return "\(artist) \(name)"
            case .track(let artist, let title):
                return "\(artist) \(title)"
            }
        }
    }

    private struct CachedResult {
        let url: URL?
        let timestamp: Date
    }

    private var cache: [Subject: CachedResult] = [:]
    private var pending: [Subject: Task<URL?, Never>] = [:]

    /// Time after which a `nil` (miss) entry is re-checked.
    private let negativeCacheTTL: TimeInterval = 300

    private let lookup: ArtworkLookupService

    public init(lookup: ArtworkLookupService = ArtworkLookupService()) {
        self.lookup = lookup
    }

    /// Resolve an artwork URL for the given subject. Uses `hint` if it is a
    /// usable URL; otherwise queries iTunes/Deezer. Returns `nil` if nothing
    /// is found.
    public func resolve(_ subject: Subject, hint: URL? = nil) async -> URL? {
        // Fast path: hint is good — return it without searching.
        if let hint, !hint.isLastFMPlaceholder {
            return hint
        }

        // Cached hit (or fresh negative cache hit)?
        if let cached = cache[subject] {
            if cached.url != nil || Date().timeIntervalSince(cached.timestamp) < negativeCacheTTL {
                return cached.url
            }
        }

        // Coalesce concurrent lookups for the same subject.
        if let inflight = pending[subject] {
            return await inflight.value
        }

        let task = Task<URL?, Never> { [lookup] in
            let results = await lookup.search(query: subject.query, limit: 5)
            // Prefer iTunes results since they are usually larger.
            if let match = results.first(where: { $0.source == .itunes && $0.imageURL != nil }) {
                return match.imageURL
            }
            return results.first(where: { $0.imageURL != nil })?.imageURL
        }
        pending[subject] = task

        let url = await task.value
        pending[subject] = nil
        cache[subject] = CachedResult(url: url, timestamp: Date())
        return url
    }

    /// Clears all cached entries.
    public func clear() {
        cache.removeAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }
}
