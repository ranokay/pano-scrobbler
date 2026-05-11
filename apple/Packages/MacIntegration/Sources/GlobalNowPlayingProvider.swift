import Foundation
import Core

public struct GlobalNowPlayingProvider: NowPlayingProvider {
    public init() {}

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public enum GlobalNowPlayingProviderNotes {
    public static let limitation = """
    macOS does not provide a stable public API for reading all other apps' Now Playing metadata.
    Direct-notarized builds may later add an unsupported provider here, but App Store-safe builds
    should use per-player providers such as Music.app or Spotify Apple Events integrations.
    """
}
