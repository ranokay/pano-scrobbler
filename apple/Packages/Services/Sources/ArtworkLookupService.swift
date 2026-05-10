import Foundation
import Core

/// Searches iTunes and Deezer for album/artist artwork — no auth required.
public struct ArtworkLookupService: Sendable {
    private let httpClient: any HTTPClient

    public init(httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - iTunes Search

    public func searchiTunes(query: String, limit: Int = 20) async throws -> [ArtworkResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else { return [] }

        let response = try await httpClient.send(
            HTTPRequest(url: url, method: "GET", headers: [:], body: nil)
        )

        guard 200..<300 ~= response.statusCode else { return [] }

        let result = try JSONDecoder().decode(ITunesSearchResponse.self, from: response.data)
        return result.results.map { item in
            ArtworkResult(
                title: item.collectionName ?? item.trackName ?? "Unknown",
                artist: item.artistName ?? "",
                imageURL: URL(string: item.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600") ?? ""),
                thumbnailURL: URL(string: item.artworkUrl100 ?? ""),
                source: .itunes
            )
        }
    }

    // MARK: - Deezer Search

    public func searchDeezer(query: String, limit: Int = 20) async throws -> [ArtworkResult] {
        var components = URLComponents(string: "https://api.deezer.com/search/album")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else { return [] }

        let response = try await httpClient.send(
            HTTPRequest(url: url, method: "GET", headers: [:], body: nil)
        )

        guard 200..<300 ~= response.statusCode else { return [] }

        let result = try JSONDecoder().decode(DeezerSearchResponse.self, from: response.data)
        return result.data.map { item in
            ArtworkResult(
                title: item.title,
                artist: item.artist?.name ?? "",
                imageURL: URL(string: item.cover_xl ?? item.cover_big ?? ""),
                thumbnailURL: URL(string: item.cover_medium ?? item.cover ?? ""),
                source: .deezer
            )
        }
    }

    // MARK: - Combined Search

    public func search(query: String, limit: Int = 10) async -> [ArtworkResult] {
        async let itunesResults = (try? searchiTunes(query: query, limit: limit)) ?? []
        async let deezerResults = (try? searchDeezer(query: query, limit: limit)) ?? []

        let (itunes, deezer) = await (itunesResults, deezerResults)
        return itunes + deezer
    }
}

// MARK: - Models

public struct ArtworkResult: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let artist: String
    public let imageURL: URL?
    public let thumbnailURL: URL?
    public let source: ArtworkSource
}

public enum ArtworkSource: String, Sendable {
    case itunes = "iTunes"
    case deezer = "Deezer"
}

// MARK: - iTunes Response

private struct ITunesSearchResponse: Codable {
    let resultCount: Int
    let results: [ITunesItem]
}

private struct ITunesItem: Codable {
    let artistName: String?
    let collectionName: String?
    let trackName: String?
    let artworkUrl100: String?
}

// MARK: - Deezer Response

private struct DeezerSearchResponse: Codable {
    let data: [DeezerAlbum]
}

private struct DeezerAlbum: Codable {
    let title: String
    let cover: String?
    let cover_medium: String?
    let cover_big: String?
    let cover_xl: String?
    let artist: DeezerArtist?
}

private struct DeezerArtist: Codable {
    let name: String
}
