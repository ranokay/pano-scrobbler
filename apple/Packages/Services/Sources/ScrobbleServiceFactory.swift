import Foundation
import Core

public enum ScrobbleServiceFactory {
    public static func makeService(
        account: UserAccount,
        credentials: ServiceCredentials,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws -> any ScrobbleService {
        switch account.type {
        case .lastFM, .libreFM, .gnuFM:
            return try LastFMService(account: account, credentials: credentials, httpClient: httpClient)
        case .listenBrainz, .customListenBrainz:
            return try ListenBrainzService(account: account, credentials: credentials, httpClient: httpClient)
        case .pleroma:
            throw ScrobbleError.unsupportedService(account.type)
        case .file:
            return try FileScrobbleService(account: account, credentials: credentials)
        }
    }

    public static func makeServices(
        accounts: [UserAccount],
        secretStore: any SecretStore,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) async -> [any ScrobbleService] {
        var services: [any ScrobbleService] = []

        for account in accounts where account.enabled {
            do {
                guard let credentials = try await secretStore.loadCredentials(reference: account.credentialReference) else {
                    continue
                }
                services.append(
                    try makeService(account: account, credentials: credentials, httpClient: httpClient)
                )
            } catch {
                continue
            }
        }

        return services
    }
}
