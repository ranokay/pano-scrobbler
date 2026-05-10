import Foundation
import Testing
import Core
@testable import Persistence

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
    let item = PendingScrobble(
        data: ScrobbleData(artist: "Artist", track: "Track", timestamp: Date(timeIntervalSince1970: 42)),
        createdAt: Date(timeIntervalSince1970: 43)
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

    try await store.remove(id: item.id)
    #expect(try await store.load(limit: 10) == [])
}
