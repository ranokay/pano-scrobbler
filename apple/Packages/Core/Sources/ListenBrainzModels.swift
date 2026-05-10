import Foundation
import Core

// MARK: - ListenBrainz Response Models

/// Top-level wrapper for /1/user/{username}/listens
public struct LBListensResponse: Codable, Sendable {
    public let payload: LBListensPayload
}

public struct LBListensPayload: Codable, Sendable {
    public let count: Int
    public let listens: [LBListen]
    public let latest_listen_ts: Int?
    public let oldest_listen_ts: Int?
}

public struct LBListen: Codable, Sendable {
    public let inserted_at: Int?
    public let listened_at: Int?
    public let recording_msid: String?
    public let playing_now: Bool?
    public let track_metadata: LBTrackMetadata
}

public struct LBTrackMetadata: Codable, Sendable {
    public let artist_name: String
    public let release_name: String?
    public let track_name: String
    public let additional_info: LBAdditionalInfo?
    public let mbid_mapping: LBMbidMapping?
}

public struct LBAdditionalInfo: Codable, Sendable {
    public let duration_ms: Int?
    public let media_player: String?
    public let submission_client: String?
    public let submission_client_version: String?
}

public struct LBMbidMapping: Codable, Sendable {
    public let artist_mbids: [String]?
    public let recording_mbid: String?
    public let release_mbid: String?
}

/// Top-level wrapper for /1/feedback/user/{username}/get-feedback
public struct LBFeedbacksResponse: Codable, Sendable {
    public let count: Int
    public let total_count: Int
    public let feedback: [LBFeedbackEntry]
}

public struct LBFeedbackEntry: Codable, Sendable {
    public let created: Int
    public let recording_mbid: String?
    public let recording_msid: String?
    public let score: Int
    public let track_metadata: LBTrackMetadata?
}

/// Top-level wrapper for /1/user/{username}/following
public struct LBFollowingResponse: Codable, Sendable {
    public let following: [String]
    public let user: String
}

/// Top-level wrapper for /1/user/{username}/listen-count
public struct LBListenCountResponse: Codable, Sendable {
    public let payload: LBListenCountPayload
}

public struct LBListenCountPayload: Codable, Sendable {
    public let count: Int
}

/// Top-level wrapper for /1/stats/user/{username}/{type}
public struct LBStatsResponse: Codable, Sendable {
    public let payload: LBStatsPayload
}

public struct LBStatsPayload: Codable, Sendable {
    public let artists: [LBStatsEntry]?
    public let releases: [LBStatsEntry]?
    public let recordings: [LBStatsEntry]?
    public let count: Int?
    public let from_ts: Int?
    public let last_updated: Int?
    public let offset: Int?
    public let range: String?
    public let to_ts: Int?
    public let total_artist_count: Int?
    public let total_release_count: Int?
    public let total_recording_count: Int?
}

public struct LBStatsEntry: Codable, Sendable {
    public let artist_mbids: [String]?
    public let artist_name: String
    public let recording_mbid: String?
    public let release_mbid: String?
    public let release_name: String?
    public let track_name: String?
    public let listen_count: Int
}

/// Validate token response
public struct LBValidateTokenResponse: Codable, Sendable {
    public let valid: Bool
    public let user_name: String?
}
