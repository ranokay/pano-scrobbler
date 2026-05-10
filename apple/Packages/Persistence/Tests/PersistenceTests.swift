import Foundation
import SQLite3
import Testing
import Core
@testable import Persistence

private let testSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test func jsonAccountStoreRoundTripsAccounts() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("accounts.json")
    let store = JSONAccountStore(fileURL: url)
    let account = UserAccount(type: .listenBrainz, username: "user")

    try await store.saveAccounts([account])
    let loaded = try await store.loadAccounts()

    #expect(loaded == [account])
}

@Test func sqlitePendingStoreRoundTripsPendingScrobbles() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("pano.sqlite")
    let store = try SQLitePersistenceStore(fileURL: url)
    let accountID = UUID()
    let item = PendingScrobble(
        data: ScrobbleData(artist: "Artist", track: "Track", timestamp: Date(timeIntervalSince1970: 42)),
        createdAt: Date(timeIntervalSince1970: 43),
        accountID: accountID,
        accountType: .lastFM,
        lastError: "Last.fm: failed"
    )

    try await store.enqueue(item)
    let loaded = try await store.load(limit: 10)

    let loadedItem = try #require(loaded.first)
    #expect(loaded.count == 1)
    #expect(loadedItem.id == item.id)
    #expect(loadedItem.data.artist == item.data.artist)
    #expect(loadedItem.data.track == item.data.track)
    #expect(abs(loadedItem.data.timestamp.timeIntervalSince(item.data.timestamp)) < 0.01)
    #expect(loadedItem.event == item.event)
    #expect(abs(loadedItem.createdAt.timeIntervalSince(item.createdAt)) < 0.01)
    #expect(loadedItem.accountID == accountID)
    #expect(loadedItem.accountType == .lastFM)
    #expect(loadedItem.lastError == "Last.fm: failed")

    try await store.remove(id: item.id)
    #expect(try await store.load(limit: 10) == [])
}

@Test func sqlitePendingStoreMigratesLegacyPendingRows() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("legacy-pano.sqlite")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    var database: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }

    let createSQL = """
    CREATE TABLE pending_scrobbles (
        id TEXT PRIMARY KEY NOT NULL,
        event TEXT NOT NULL,
        created_at REAL NOT NULL,
        payload TEXT NOT NULL,
        last_error TEXT
    );
    """
    #expect(sqlite3_exec(database, createSQL, nil, nil, nil) == SQLITE_OK)

    let id = UUID()
    let data = ScrobbleData(artist: "Legacy", track: "Track", timestamp: Date(timeIntervalSince1970: 42))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let payload = String(decoding: try encoder.encode(data), as: UTF8.self)

    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(
        database,
        "INSERT INTO pending_scrobbles (id, event, created_at, payload, last_error) VALUES (?, ?, ?, ?, ?);",
        -1,
        &statement,
        nil
    ) == SQLITE_OK)
    sqlite3_bind_text(statement, 1, id.uuidString, -1, testSQLiteTransient)
    sqlite3_bind_text(statement, 2, "scrobble", -1, testSQLiteTransient)
    sqlite3_bind_double(statement, 3, 43)
    sqlite3_bind_text(statement, 4, payload, -1, testSQLiteTransient)
    sqlite3_bind_text(statement, 5, "legacy error", -1, testSQLiteTransient)
    #expect(sqlite3_step(statement) == SQLITE_DONE)
    sqlite3_finalize(statement)

    sqlite3_close(database)
    database = nil

    let store = try SQLitePersistenceStore(fileURL: url)
    let loaded = try await store.load(limit: 10)
    let item = try #require(loaded.first)

    #expect(item.id == id)
    #expect(item.data.artist == "Legacy")
    #expect(item.accountID == nil)
    #expect(item.accountType == nil)
    #expect(item.lastError == "legacy error")
}
