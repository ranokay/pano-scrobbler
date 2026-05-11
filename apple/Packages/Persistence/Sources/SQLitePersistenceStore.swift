import Foundation
import Core
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLitePersistenceStore: PendingScrobbleStore, @unchecked Sendable {
    private let database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.arn.scrobble.mac.sqlite")

    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &opened, flags, nil) == SQLITE_OK else {
            throw SQLiteStoreError.message("Failed to open SQLite database.")
        }

        self.database = opened
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try Self.initializeSchema(opened)
    }

    deinit {
        sqlite3_close(database)
    }

    private static func initializeSchema(_ database: OpaquePointer?) throws {
        let createSQL = """
        CREATE TABLE IF NOT EXISTS pending_scrobbles (
            id TEXT PRIMARY KEY NOT NULL,
            event TEXT NOT NULL,
            created_at REAL NOT NULL,
            payload TEXT NOT NULL,
            account_id TEXT,
            account_type TEXT,
            last_error TEXT
        );
        """

        guard sqlite3_exec(database, createSQL, nil, nil, nil) == SQLITE_OK else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
                ?? "Failed to initialize SQLite schema."
            throw SQLiteStoreError.message(message)
        }

        let columns = try tableColumns(database, tableName: "pending_scrobbles")
        if !columns.contains("account_id") {
            try execute(database, "ALTER TABLE pending_scrobbles ADD COLUMN account_id TEXT;")
        }
        if !columns.contains("account_type") {
            try execute(database, "ALTER TABLE pending_scrobbles ADD COLUMN account_type TEXT;")
        }
    }

    public func enqueue(_ item: PendingScrobble) async throws {
        try queue.sync {
            try enqueueLocked(item)
        }
    }

    private func enqueueLocked(_ item: PendingScrobble) throws {
        let payload = String(decoding: try encoder.encode(item.data), as: UTF8.self)
        let sql = """
            INSERT OR REPLACE INTO pending_scrobbles
            (id, event, created_at, payload, account_id, account_type, last_error)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, item.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, item.event, -1, sqliteTransient)
        sqlite3_bind_double(statement, 3, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, payload, -1, sqliteTransient)
        bindOptionalText(statement, index: 5, value: item.accountID?.uuidString)
        bindOptionalText(statement, index: 6, value: item.accountType?.rawValue)
        bindOptionalText(statement, index: 7, value: item.lastError)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    public func load(limit: Int) async throws -> [PendingScrobble] {
        try queue.sync {
            try loadLocked(limit: limit)
        }
    }

    private func loadLocked(limit: Int) throws -> [PendingScrobble] {
        let statement = try prepare(
            """
            SELECT id, event, created_at, payload, account_id, account_type, last_error
            FROM pending_scrobbles
            ORDER BY created_at ASC
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))
        var items: [PendingScrobble] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqliteText(statement, column: 0),
                  let id = UUID(uuidString: idText),
                  let event = sqliteText(statement, column: 1),
                  let payload = sqliteText(statement, column: 3),
                  let payloadData = payload.data(using: .utf8)
            else {
                continue
            }

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let data: ScrobbleData
            do {
                data = try decoder.decode(ScrobbleData.self, from: payloadData)
            } catch {
                continue
            }
            let accountID = sqliteText(statement, column: 4).flatMap(UUID.init(uuidString:))
            let accountType = sqliteText(statement, column: 5).flatMap(AccountType.init(rawValue:))
            let error = sqliteText(statement, column: 6)

            items.append(
                PendingScrobble(
                    id: id,
                    data: data,
                    event: event,
                    createdAt: createdAt,
                    accountID: accountID,
                    accountType: accountType,
                    lastError: error
                )
            )
        }

        return items
    }

    public func remove(id: UUID) async throws {
        try queue.sync {
            try removeLocked(id: id)
        }
    }

    private func removeLocked(id: UUID) throws {
        let statement = try prepare("DELETE FROM pending_scrobbles WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    private static func execute(_ database: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            if let message = sqlite3_errmsg(database) {
                throw SQLiteStoreError.message(String(cString: message))
            }
            throw SQLiteStoreError.message("Unknown SQLite error.")
        }
    }

    private static func tableColumns(_ database: OpaquePointer?, tableName: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(tableName));", -1, &statement, nil) == SQLITE_OK else {
            if let message = sqlite3_errmsg(database) {
                throw SQLiteStoreError.message(String(cString: message))
            }
            throw SQLiteStoreError.message("Could not inspect SQLite schema.")
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        return statement
    }

    private func lastError() -> SQLiteStoreError {
        if let message = sqlite3_errmsg(database) {
            return .message(String(cString: message))
        }
        return .message("Unknown SQLite error.")
    }

    private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func sqliteText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }
}

public enum SQLiteStoreError: LocalizedError, Sendable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
