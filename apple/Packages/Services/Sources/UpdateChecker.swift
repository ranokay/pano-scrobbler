import Foundation
import Core

/// Checks GitHub releases for a newer version of the app.
public struct UpdateChecker: Sendable {
    private let owner: String
    private let repo: String
    private let httpClient: any HTTPClient

    public init(
        owner: String = "kawaiiDango",
        repo: String = "pano-scrobbler",
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.owner = owner
        self.repo = repo
        self.httpClient = httpClient
    }

    /// Check for a newer release. Returns nil if up-to-date or on error.
    public func checkForUpdate(currentVersion: String) async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return nil
        }

        do {
            let response = try await httpClient.send(
                HTTPRequest(url: url, method: "GET", headers: [
                    "Accept": "application/vnd.github+json"
                ], body: nil)
            )

            guard 200..<300 ~= response.statusCode else { return nil }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: response.data)
            let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet.letters.union(.punctuationCharacters))

            if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                return UpdateInfo(
                    version: release.tag_name,
                    changelog: release.body ?? "",
                    downloadURL: URL(string: release.html_url),
                    publishedAt: release.published_at
                )
            }
        } catch {
            // silently fail
        }

        return nil
    }
}

// MARK: - Models

public struct UpdateInfo: Sendable {
    public let version: String
    public let changelog: String
    public let downloadURL: URL?
    public let publishedAt: String?
}

private struct GitHubRelease: Codable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
}
