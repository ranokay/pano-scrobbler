import AppKit
import Foundation
import Core
import MacIntegration
import Persistence
import Services

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences = AppPreferences()
    @Published var accounts: [UserAccount] = []
    @Published var metadataRules = MetadataRulesSnapshot()
    @Published var status = NowPlayingStatus()
    @Published var logs: [String] = []
    @Published var logFilter: String = ""
    @Published var pendingCount = 0
    @Published var selectedSection: AppSection? = .nowPlaying
    @Published var scrobbleHistory: [LastFMTrack] = []
    @Published var historyPage = PageInfo()
    @Published var isLoadingHistory = false
    @Published var userProfile: LastFMUser?

    // Charts
    @Published var chartArtists: [LastFMArtist] = []
    @Published var chartAlbums: [LastFMAlbum] = []
    @Published var chartTracks: [LastFMTrack] = []
    @Published var chartPeriod: LastFMPeriod = .month
    @Published var isLoadingCharts = false

    // Friends
    @Published var friends: [LastFMUser] = []
    @Published var friendsPage = PageInfo()
    @Published var isLoadingFriends = false

    // Search
    @Published var searchQuery = ""
    @Published var searchArtists: [LastFMArtist] = []
    @Published var searchAlbums: [LastFMAlbum] = []
    @Published var searchTracks: [LastFMTrack] = []
    @Published var isSearching = false

    // Discord RPC
    @Published var discordEnabled = UserDefaults.standard.bool(forKey: "discordRPCEnabled") &&
        AppConfiguration.discordClientID != nil
    @Published var discordConnected = false
    var discordAvailable: Bool { AppConfiguration.discordClientID != nil }

    let paths: AppPaths

    private let accountStore: JSONAccountStore
    private let preferencesStore: JSONPreferencesStore
    private let rulesStore: JSONMetadataRulesStore
    private let secretStore: KeychainSecretStore
    private let pendingStore: any PendingScrobbleStore
    private let notifications = MacNotificationPresenter()
    private let statusItem = StatusItemController()
    private let engine: ScrobbleEngine
    private let nowPlayingProvider = AppleScriptNowPlayingProvider()
    private var engineTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private lazy var discordRPC: DiscordRichPresence? = {
        guard let clientID = AppConfiguration.discordClientID else { return nil }
        return DiscordRichPresence(clientId: clientID)
    }()

    init() {
        self.paths = AppPaths.default
        self.accountStore = JSONAccountStore(fileURL: paths.accountsURL)
        self.preferencesStore = JSONPreferencesStore(fileURL: paths.preferencesURL)
        self.rulesStore = JSONMetadataRulesStore(fileURL: paths.rulesURL)
        self.secretStore = KeychainSecretStore()

        do {
            self.pendingStore = try SQLitePersistenceStore(fileURL: paths.databaseURL)
        } catch {
            self.pendingStore = InMemoryPendingScrobbleStore()
        }

        self.engine = ScrobbleEngine(
            pendingStore: pendingStore,
            notificationPresenter: notifications
        )

        statusItem.onOpen = {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        statusItem.onSettings = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        statusItem.onQuit = {
            NSApp.terminate(nil)
        }
        statusItem.onLove = { [weak self] in
            guard let self, let data = self.status.data else { return }
            Task {
                await self.toggleLove(artist: data.artist, track: data.track, loved: true)
            }
        }

        appendLog("Native macOS scaffold started.")
        Task { await bootstrap() }
    }

    deinit {
        engineTask?.cancel()
        statusTask?.cancel()
        retryTask?.cancel()
    }

    func bootstrap() async {
        await notifications.requestAuthorization()

        do {
            preferences = try await preferencesStore.load()
            accounts = try await accountStore.loadAccounts()
            metadataRules = try await rulesStore.load()
            await engine.updatePreferences(preferences)
            await engine.updatePipeline(metadataRules.pipeline)
            await reloadServices()
            startEngine()
            startStatusPolling()
            startPendingRetryLoop()
            appendLog("Loaded \(accounts.count) account(s).")
        } catch {
            appendLog("Startup failed: \(error.localizedDescription)")
        }
    }

    func reloadServices() async {
        let services = await ScrobbleServiceFactory.makeServices(accounts: accounts, secretStore: secretStore)
        await engine.updateServices(services)
        appendLog("Service reload completed: \(services.count) active service(s).")
    }

    func savePreferences() async {
        do {
            try await preferencesStore.save(preferences)
            await engine.updatePreferences(preferences)
            appendLog("Preferences saved.")
        } catch {
            appendLog("Could not save preferences: \(error.localizedDescription)")
        }
    }

    func saveRules() async {
        do {
            try await rulesStore.save(metadataRules)
            await engine.updatePipeline(metadataRules.pipeline)
            appendLog("Metadata rules saved.")
        } catch {
            appendLog("Could not save metadata rules: \(error.localizedDescription)")
        }
    }

    func retryPendingNow() async {
        let summary = await engine.retryPending()
        pendingCount = (try? await pendingStore.load(limit: 200).count) ?? pendingCount

        if summary.attempted > 0 {
            appendLog(
                "Retried \(summary.attempted) pending scrobble(s): \(summary.succeeded) succeeded, \(summary.failed) failed."
            )
        }
    }

    func exportBundle() {
        let panel = NSSavePanel()
        panel.title = "Export Pano Scrobbler Data"
        panel.nameFieldStringValue = "pano-scrobbler-export.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let bundle = ExportBundle(
            preferences: preferences,
            accounts: accounts,
            simpleEdits: metadataRules.simpleEdits,
            regexEdits: metadataRules.regexEdits,
            blockRules: metadataRules.blockRules
        )

        do {
            try ImportExport.encode(bundle).write(to: url, options: [.atomic])
            appendLog("Exported data to \(url.path).")
        } catch {
            appendLog("Export failed: \(error.localizedDescription)")
        }
    }

    func importBundle() {
        let panel = NSOpenPanel()
        panel.title = "Import Pano Scrobbler Data"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            do {
                let data = try Data(contentsOf: url)
                let bundle = try ImportExport.decode(data)
                preferences = bundle.preferences
                accounts = bundle.accounts
                metadataRules = MetadataRulesSnapshot(
                    simpleEdits: bundle.simpleEdits,
                    regexEdits: bundle.regexEdits,
                    blockRules: bundle.blockRules
                )
                try await preferencesStore.save(preferences)
                try await accountStore.saveAccounts(accounts)
                try await rulesStore.save(metadataRules)
                await engine.updatePreferences(preferences)
                await engine.updatePipeline(metadataRules.pipeline)
                await reloadServices()
                appendLog("Imported data from \(url.path). Account secrets remain in Keychain and are not included in exports.")
            } catch {
                appendLog("Import failed: \(error.localizedDescription)")
            }
        }
    }

    func addListenBrainzAccount(username: String, token: String) async {
        await addAccount(
            type: .listenBrainz,
            username: username,
            credentials: ServiceCredentials(token: token)
        )
    }

    func addLastFMAccount(username: String, apiKey: String, apiSecret: String, sessionKey: String) async {
        await addAccount(
            type: .lastFM,
            username: username,
            credentials: ServiceCredentials(apiKey: apiKey, apiSecret: apiSecret, sessionKey: sessionKey)
        )
    }

    /// Authenticate with Last.fm via OAuth browser flow.
    /// Opens the browser for authorization, then polls until the token is authorized.
    func authenticateLastFMViaOAuth(
        apiKey: String,
        apiSecret: String,
        onStatusUpdate: @escaping @MainActor (String) -> Void
    ) async throws {
        onStatusUpdate("Getting token…")
        let token = try await LastFMAuth.getToken(apiKey: apiKey, apiSecret: apiSecret)

        let authURL = LastFMAuth.authorizationURL(apiKey: apiKey, token: token)
        onStatusUpdate("Opening browser…")
        NSWorkspace.shared.open(authURL)

        onStatusUpdate("Waiting for authorization…")
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            do {
                let (username, sessionKey) = try await LastFMAuth.getSession(
                    apiKey: apiKey,
                    apiSecret: apiSecret,
                    token: token
                )

                await addLastFMAccount(
                    username: username,
                    apiKey: apiKey,
                    apiSecret: apiSecret,
                    sessionKey: sessionKey
                )
                onStatusUpdate("Authenticated as \(username)!")
                return
            } catch let error as ScrobbleError where error.isAuthPending {
                // Token not yet authorized, keep polling
                continue
            }
        }

        throw ScrobbleError.invalidResponse("Authorization timed out. Please try again.")
    }

    func addFileAccount(fileURL: URL) async {
        await addAccount(
            type: .file,
            username: fileURL.lastPathComponent,
            credentials: ServiceCredentials(fileURL: fileURL)
        )
    }

    func removeAccounts(at offsets: IndexSet) {
        let removed = offsets.map { accounts[$0] }
        accounts.remove(atOffsets: offsets)

        Task {
            for account in removed {
                try? await secretStore.deleteCredentials(reference: account.credentialReference)
            }
            try? await accountStore.saveAccounts(accounts)
            await reloadServices()
        }
    }

    func addAllowedAppID(_ appID: String) {
        let value = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        preferences.allowedAppIDs.insert(value)
        preferences.blockedAppIDs.remove(value)
        Task { await savePreferences() }
    }

    func removeAllowedAppIDs(at offsets: IndexSet) {
        let sorted = preferences.allowedAppIDs.sorted()
        for index in offsets {
            preferences.allowedAppIDs.remove(sorted[index])
        }
        Task { await savePreferences() }
    }

    func addBlockedAppID(_ appID: String) {
        let value = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        preferences.blockedAppIDs.insert(value)
        preferences.allowedAppIDs.remove(value)
        Task { await savePreferences() }
    }

    func removeBlockedAppIDs(at offsets: IndexSet) {
        let sorted = preferences.blockedAppIDs.sorted()
        for index in offsets {
            preferences.blockedAppIDs.remove(sorted[index])
        }
        Task { await savePreferences() }
    }

    func addBlockRule(field: BlockRule.Field, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        metadataRules.blockRules.append(BlockRule(field: field, value: trimmed))
        Task { await saveRules() }
    }

    func removeBlockRules(at offsets: IndexSet) {
        metadataRules.blockRules.remove(atOffsets: offsets)
        Task { await saveRules() }
    }

    func addSimpleEdit(
        matchArtist: String,
        matchTrack: String,
        replacementArtist: String,
        replacementTrack: String,
        replacementAlbum: String,
        replacementAlbumArtist: String
    ) {
        let edit = SimpleEdit(
            matchArtist: matchArtist.trimmingCharacters(in: .whitespacesAndNewlines),
            matchTrack: matchTrack.trimmingCharacters(in: .whitespacesAndNewlines),
            replacementArtist: replacementArtist.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            replacementTrack: replacementTrack.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            replacementAlbum: replacementAlbum.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            replacementAlbumArtist: replacementAlbumArtist.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        guard !edit.matchArtist.isEmpty, !edit.matchTrack.isEmpty else {
            return
        }

        metadataRules.simpleEdits.append(edit)
        Task { await saveRules() }
    }

    func removeSimpleEdits(at offsets: IndexSet) {
        metadataRules.simpleEdits.remove(atOffsets: offsets)
        Task { await saveRules() }
    }

    func addRegexEdit(field: RegexEdit.Field, pattern: String, replacement: String) {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }

        metadataRules.regexEdits.append(
            RegexEdit(field: field, pattern: pattern, replacement: replacement)
        )
        Task { await saveRules() }
    }

    func removeRegexEdits(at offsets: IndexSet) {
        metadataRules.regexEdits.remove(atOffsets: offsets)
        Task { await saveRules() }
    }

    private func addAccount(type: AccountType, username: String, credentials: ServiceCredentials) async {
        let account = UserAccount(type: type, username: username.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            try await secretStore.saveCredentials(credentials, reference: account.credentialReference)
            accounts.removeAll { $0.type == type && $0.username == account.username }
            accounts.append(account)
            try await accountStore.saveAccounts(accounts)
            await reloadServices()
            appendLog("Added \(type.displayName) account for \(account.username).")
        } catch {
            appendLog("Could not add account: \(error.localizedDescription)")
        }
    }

    private func startEngine() {
        guard engineTask == nil else { return }
        engineTask = Task { [engine, nowPlayingProvider] in
            await engine.run(provider: nowPlayingProvider)
        }
    }

    private func startStatusPolling() {
        guard statusTask == nil else { return }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let status = await engine.status()
                let pending = (try? await pendingStore.load(limit: 200).count) ?? 0
                await MainActor.run {
                    self.status = status
                    self.pendingCount = pending
                    self.statusItem.update(status: status)
                    self.updateDiscordPresence(status: status)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Discord RPC

    func toggleDiscord(_ enabled: Bool) {
        guard discordAvailable, let discordRPC else {
            discordEnabled = false
            discordConnected = false
            UserDefaults.standard.set(false, forKey: "discordRPCEnabled")
            appendLog("Discord Rich Presence is not configured for this build.")
            return
        }

        discordEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "discordRPCEnabled")

        if enabled {
            discordConnected = discordRPC.connect()
            if discordConnected {
                appendLog("Discord Rich Presence connected.")
            } else {
                appendLog("Discord Rich Presence: could not connect. Is Discord running?")
            }
        } else {
            discordRPC.clearActivity()
            discordRPC.disconnect()
            discordConnected = false
            appendLog("Discord Rich Presence disconnected.")
        }
    }

    private func updateDiscordPresence(status: NowPlayingStatus) {
        guard let discordRPC else { return }

        guard discordEnabled, let data = status.data else {
            if discordEnabled && status.state != .playing {
                discordRPC.clearActivity()
            }
            return
        }

        guard status.state == .playing else {
            discordRPC.clearActivity()
            return
        }

        if !discordConnected {
            discordConnected = discordRPC.connect()
        }

        guard discordConnected else { return }

        let elapsed = Date().timeIntervalSince(data.timestamp)
        discordRPC.updateActivity(
            track: data.track,
            artist: data.artist,
            album: data.album,
            elapsed: elapsed,
            duration: data.duration,
            artworkURL: data.artworkURL?.absoluteString
        )
    }

    private func startPendingRetryLoop() {
        guard retryTask == nil else { return }

        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                await retryPendingNow()
            }
        }
    }

    var filteredLogs: [String] {
        guard !logFilter.isEmpty else { return logs }
        return logs.filter { $0.localizedCaseInsensitiveContains(logFilter) }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func resetPreferences() async {
        preferences = AppPreferences()
        await savePreferences()
    }

    // MARK: - History / Read API

    func loadHistory(page: Int = 1) {
        guard !isLoadingHistory else { return }

        Task {
            isLoadingHistory = true
            defer { isLoadingHistory = false }

            guard let service = lastFMService else {
                appendLog("No Last.fm account configured for history.")
                return
            }

            do {
                let result = try await service.getRecents(page: page)
                if page == 1 {
                    scrobbleHistory = result.entries
                } else {
                    scrobbleHistory.append(contentsOf: result.entries)
                }
                historyPage = result.attr
                appendLog("Loaded page \(page) of scrobble history (\(result.entries.count) tracks).")
            } catch {
                appendLog("Failed to load history: \(error.localizedDescription)")
            }
        }
    }

    func loadUserProfile() {
        Task {
            guard let service = lastFMService else { return }
            do {
                userProfile = try await service.getUserInfo()
                appendLog("Loaded user profile: \(userProfile?.name ?? "unknown").")
            } catch {
                appendLog("Failed to load profile: \(error.localizedDescription)")
            }
        }
    }

    var lastFMService: LastFMService? {
        guard let account = accounts.first(where: { $0.type == .lastFM }) else { return nil }
        guard let creds = try? KeychainSecretStore().loadCredentialsSync(reference: account.credentialReference) else { return nil }
        return try? LastFMService(account: account, credentials: creds)
    }

    func toggleLove(artist: String, track: String, loved: Bool) async {
        guard let service = lastFMService else {
            appendLog("No Last.fm account for love/unlove.")
            return
        }
        do {
            let data = ScrobbleData(artist: artist, track: track, album: nil, albumArtist: nil, duration: nil, timestamp: Date())
            if loved {
                _ = try await service.love(data)
                appendLog("Loved: \(artist) — \(track)")
            } else {
                _ = try await service.unlove(data)
                appendLog("Unloved: \(artist) — \(track)")
            }
        } catch {
            appendLog("Love/unlove failed: \(error.localizedDescription)")
        }
    }

    func deleteScrobble(artist: String, track: String, timestamp: Date) async {
        guard let service = lastFMService else {
            appendLog("No Last.fm account for delete.")
            return
        }
        do {
            let data = ScrobbleData(artist: artist, track: track, album: nil, albumArtist: nil, duration: nil, timestamp: timestamp)
            try await service.delete(data)
            scrobbleHistory.removeAll { $0.artist.name == artist && $0.name == track && $0.timestamp == timestamp }
            appendLog("Deleted scrobble: \(artist) — \(track)")
        } catch {
            appendLog("Delete scrobble failed: \(error.localizedDescription)")
        }
    }

    func manualScrobble(_ data: ScrobbleData) async {
        let summary = await engine.scrobbleManually(data)
        appendLog("Manual scrobble: \(data.artist) — \(data.track) → \(summary)")
    }

    // MARK: - Charts

    func loadCharts(period: LastFMPeriod? = nil) {
        if let period { chartPeriod = period }
        guard !isLoadingCharts else { return }

        Task {
            isLoadingCharts = true
            defer { isLoadingCharts = false }

            guard let service = lastFMService else {
                appendLog("No Last.fm account for charts.")
                return
            }

            do {
                async let artists = service.getTopArtists(period: chartPeriod, limit: 25)
                async let albums = service.getTopAlbums(period: chartPeriod, limit: 25)
                async let tracks = service.getTopTracks(period: chartPeriod, limit: 25)

                let (a, al, t) = try await (artists, albums, tracks)
                chartArtists = a.entries
                chartAlbums = al.entries
                chartTracks = t.entries
                appendLog("Loaded charts for \(chartPeriod.displayName).")
            } catch {
                appendLog("Failed to load charts: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Friends

    func loadFriends(page: Int = 1) {
        guard !isLoadingFriends else { return }

        Task {
            isLoadingFriends = true
            defer { isLoadingFriends = false }

            guard let service = lastFMService else {
                appendLog("No Last.fm account for friends.")
                return
            }

            do {
                let result = try await service.getFriends(page: page, limit: 50)
                if page == 1 {
                    friends = result.entries
                } else {
                    friends.append(contentsOf: result.entries)
                }
                friendsPage = result.attr
                appendLog("Loaded \(result.entries.count) friend(s).")
            } catch {
                appendLog("Failed to load friends: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Search

    private var searchTask: Task<Void, Never>?

    func performSearch(query: String) {
        searchQuery = query
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchArtists = []
            searchAlbums = []
            searchTracks = []
            return
        }

        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            guard let service = lastFMService else { return }

            // Last.fm doesn't have a unified search endpoint with session key,
            // so we search for the term in top results from user library
            // For a proper search we'd need the unauthenticated API, but let's
            // use the charts endpoint filtered client-side for now.
            // TODO: Implement proper Last.fm search endpoints (artist.search, etc.)
            do {
                // Use getTopArtists/Tracks with large limit and filter client-side
                // This is a pragmatic first pass
                async let artistsResult = service.getTopArtists(period: .overall, limit: 100)
                async let tracksResult = service.getTopTracks(period: .overall, limit: 100)
                async let albumsResult = service.getTopAlbums(period: .overall, limit: 100)

                let (ar, tr, al) = try await (artistsResult, tracksResult, albumsResult)
                guard !Task.isCancelled else { return }

                let q = trimmed.lowercased()
                searchArtists = ar.entries.filter { $0.name.lowercased().contains(q) }
                searchTracks = tr.entries.filter {
                    $0.name.lowercased().contains(q) || $0.artist.name.lowercased().contains(q)
                }
                searchAlbums = al.entries.filter {
                    $0.name.lowercased().contains(q) || ($0.artist?.name.lowercased().contains(q) ?? false)
                }
            } catch {
                guard !Task.isCancelled else { return }
                appendLog("Search failed: \(error.localizedDescription)")
            }
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        logs.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
        logs = Array(logs.prefix(200))
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing"
    case history = "History"
    case charts = "Charts"
    case friends = "Friends"
    case profile = "Profile"
    case search = "Search"
    case random = "Random"
    case collage = "Collage"
    case manualScrobble = "Manual Scrobble"
    case fileScrobble = "Scrobble from File"
    case artworkSearch = "Artwork Search"
    case accounts = "Accounts"
    case apps = "Apps"
    case edits = "Edits & Blocks"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .nowPlaying: "music.note.list"
        case .history: "clock.arrow.circlepath"
        case .charts: "chart.bar.fill"
        case .friends: "person.2.fill"
        case .profile: "person.circle"
        case .search: "magnifyingglass"
        case .random: "dice"
        case .collage: "photo.artframe"
        case .manualScrobble: "pencil.line"
        case .fileScrobble: "doc.text"
        case .artworkSearch: "photo.on.rectangle"
        case .accounts: "person.crop.circle"
        case .apps: "app.badge"
        case .edits: "slider.horizontal.3"
        case .settings: "gearshape"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

private enum AppConfiguration {
    static var discordClientID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DiscordClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}
