import Foundation
import Core

public struct PleromaService: ScrobbleService {
    public var account: UserAccount

    public init(account: UserAccount, credentials: ServiceCredentials) throws {
        guard credentials.token?.nilIfEmpty != nil else {
            throw ScrobbleError.missingCredentials(.pleroma)
        }

        self.account = account
    }

    public func updateNowPlaying(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.notImplemented("Pleroma now-playing submission is scaffolded but not implemented yet.")
    }

    public func scrobble(_ data: ScrobbleData) async throws -> ScrobbleResult {
        throw ScrobbleError.notImplemented("Pleroma scrobbling is scaffolded but not implemented yet.")
    }
}
