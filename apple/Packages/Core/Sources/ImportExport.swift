import Foundation

public struct ExportBundle: Codable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var preferences: AppPreferences
    public var accounts: [UserAccount]
    public var simpleEdits: [SimpleEdit]
    public var regexEdits: [RegexEdit]
    public var blockRules: [BlockRule]

    public init(
        formatVersion: Int = 1,
        exportedAt: Date = Date(),
        preferences: AppPreferences,
        accounts: [UserAccount],
        simpleEdits: [SimpleEdit] = [],
        regexEdits: [RegexEdit] = [],
        blockRules: [BlockRule] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.accounts = accounts
        self.simpleEdits = simpleEdits
        self.regexEdits = regexEdits
        self.blockRules = blockRules
    }
}

public enum ImportExport {
    public static let currentFormatVersion = 1

    public static func encode(_ bundle: ExportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    public static func decode(_ data: Data) throws -> ExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportBundle.self, from: data)
    }
}
