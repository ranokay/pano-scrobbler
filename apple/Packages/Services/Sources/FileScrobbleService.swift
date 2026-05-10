import Foundation
import Core

public enum FileScrobbleFormat: String, Codable, Sendable {
    case jsonl
    case csv
}

public struct FileScrobbleService: ScrobbleService {
    public var account: UserAccount

    private let fileURL: URL
    private let format: FileScrobbleFormat

    public init(account: UserAccount, credentials: ServiceCredentials, format: FileScrobbleFormat = .jsonl) throws {
        guard let fileURL = credentials.fileURL else {
            throw ScrobbleError.missingCredentials(.file)
        }

        self.account = account
        self.fileURL = fileURL
        self.format = format
    }

    public func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        ScrobbleResult()
    }

    public func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let line: String = switch format {
        case .jsonl:
            try jsonLine(for: data)
        case .csv:
            csvLine(for: data)
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))

        return ScrobbleResult()
    }

    private func jsonLine(for data: ScrobbleData) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)
        return String(decoding: encoded, as: UTF8.self)
    }

    private func csvLine(for data: ScrobbleData) -> String {
        [
            String(Int(data.timestamp.timeIntervalSince1970)),
            data.artist,
            data.track,
            data.album ?? "",
            data.albumArtist ?? "",
            data.appID ?? ""
        ].map(Self.csvEscape).joined(separator: ",")
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
