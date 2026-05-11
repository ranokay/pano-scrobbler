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

    private struct CachedImageData {
        let data: Data
        let timestamp: Date
    }

    private var cache: [Subject: CachedResult] = [:]
    private var pending: [Subject: Task<URL?, Never>] = [:]
    private var imageDataCache: [URL: CachedImageData] = [:]
    private var imageDataOrder: [URL] = []
    private var imageDataPending: [URL: Task<Data?, Never>] = [:]

    /// Time after which a `nil` (miss) entry is re-checked.
    private let negativeCacheTTL: TimeInterval = 300
    private let maxImageDataEntries = 300

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

    /// Fetches and caches raw image bytes for an artwork URL. This avoids
    /// `AsyncImage` re-downloading/re-decoding artwork every time SwiftUI
    /// recreates rows during tab switches or list scrolling.
    public func imageData(for url: URL) async -> Data? {
        if let cached = imageDataCache[url] {
            touchImageData(url)
            return cached.data
        }

        if let inflight = imageDataPending[url] {
            return await inflight.value
        }

        let task = Task<Data?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
        imageDataPending[url] = task

        guard let data = await task.value else {
            imageDataPending[url] = nil
            return nil
        }

        imageDataPending[url] = nil
        imageDataCache[url] = CachedImageData(data: data, timestamp: Date())
        touchImageData(url)
        evictImageDataIfNeeded()
        return data
    }

    /// Clears all cached entries.
    public func clear() {
        cache.removeAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        imageDataCache.removeAll()
        imageDataOrder.removeAll()
        imageDataPending.values.forEach { $0.cancel() }
        imageDataPending.removeAll()
    }

    private func touchImageData(_ url: URL) {
        imageDataOrder.removeAll { $0 == url }
        imageDataOrder.append(url)
    }

    private func evictImageDataIfNeeded() {
        while imageDataOrder.count > maxImageDataEntries {
            let url = imageDataOrder.removeFirst()
            imageDataCache.removeValue(forKey: url)
        }
    }
}
