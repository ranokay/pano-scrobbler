import Foundation
import Core

public struct NoopPlayerCommandProvider: PlayerCommandProvider {
    public init() {}

    public func skip(sessionID: String) async throws {
        throw ScrobbleError.notImplemented("Generic skip is not available for this macOS provider.")
    }

    public func mute(sessionID: String) async throws {
        throw ScrobbleError.notImplemented("Generic mute is not available for this macOS provider.")
    }

    public func unmute(sessionID: String) async throws {
        throw ScrobbleError.notImplemented("Generic unmute is not available for this macOS provider.")
    }
}
