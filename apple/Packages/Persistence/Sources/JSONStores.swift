import Foundation
import Core

public actor JSONAccountStore: AccountStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadAccounts() async throws -> [UserAccount] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([UserAccount].self, from: data)
    }

    public func saveAccounts(_ accounts: [UserAccount]) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor JSONPreferencesStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async throws -> AppPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppPreferences()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppPreferences.self, from: data)
    }

    public func save(_ preferences: AppPreferences) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public struct MetadataRulesSnapshot: Codable, Equatable, Sendable {
    public var simpleEdits: [SimpleEdit]
    public var regexEdits: [RegexEdit]
    public var blockRules: [BlockRule]

    public init(simpleEdits: [SimpleEdit] = [], regexEdits: [RegexEdit] = [], blockRules: [BlockRule] = []) {
        self.simpleEdits = simpleEdits
        self.regexEdits = regexEdits
        self.blockRules = blockRules
    }

    public var pipeline: MetadataPipeline {
        MetadataPipeline(simpleEdits: simpleEdits, regexEdits: regexEdits, blockRules: blockRules)
    }
}

public actor JSONMetadataRulesStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async throws -> MetadataRulesSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return MetadataRulesSnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MetadataRulesSnapshot.self, from: data)
    }

    public func save(_ snapshot: MetadataRulesSnapshot) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
