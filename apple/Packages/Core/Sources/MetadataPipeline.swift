import Foundation

public enum BlockAction: String, Codable, Sendable {
    case skip
    case mute
    case ignore
}

public struct BlockRule: Codable, Hashable, Identifiable, Sendable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case artist
        case track
        case album
        case albumArtist
        case appID
    }

    public var id: UUID
    public var field: Field
    public var value: String
    public var action: BlockAction
    public var caseSensitive: Bool
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        field: Field,
        value: String,
        action: BlockAction = .ignore,
        caseSensitive: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.field = field
        self.value = value
        self.action = action
        self.caseSensitive = caseSensitive
        self.enabled = enabled
    }

    public func matches(_ data: ScrobbleData) -> Bool {
        let candidate: String = switch field {
        case .artist: data.artist
        case .track: data.track
        case .album: data.album ?? ""
        case .albumArtist: data.albumArtist ?? ""
        case .appID: data.appID ?? ""
        }

        if caseSensitive {
            return candidate == value
        } else {
            return candidate.localizedCaseInsensitiveCompare(value) == .orderedSame
        }
    }
}

public struct SimpleEdit: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var matchArtist: String
    public var matchTrack: String
    public var replacementArtist: String?
    public var replacementTrack: String?
    public var replacementAlbum: String?
    public var replacementAlbumArtist: String?
    public var continueMatching: Bool
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        matchArtist: String,
        matchTrack: String,
        replacementArtist: String? = nil,
        replacementTrack: String? = nil,
        replacementAlbum: String? = nil,
        replacementAlbumArtist: String? = nil,
        continueMatching: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.matchArtist = matchArtist
        self.matchTrack = matchTrack
        self.replacementArtist = replacementArtist
        self.replacementTrack = replacementTrack
        self.replacementAlbum = replacementAlbum
        self.replacementAlbumArtist = replacementAlbumArtist
        self.continueMatching = continueMatching
        self.enabled = enabled
    }

    public func apply(to data: ScrobbleData) -> ScrobbleData? {
        guard enabled,
              data.artist.localizedCaseInsensitiveCompare(matchArtist) == .orderedSame,
              data.track.localizedCaseInsensitiveCompare(matchTrack) == .orderedSame
        else {
            return nil
        }

        var edited = data
        edited.artist = replacementArtist?.nilIfEmpty ?? edited.artist
        edited.track = replacementTrack?.nilIfEmpty ?? edited.track
        edited.album = replacementAlbum?.nilIfEmpty ?? edited.album
        edited.albumArtist = replacementAlbumArtist?.nilIfEmpty ?? edited.albumArtist
        return edited.trimmed()
    }
}

public struct RegexEdit: Codable, Hashable, Identifiable, Sendable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case artist
        case track
        case album
        case albumArtist
    }

    public var id: UUID
    public var field: Field
    public var pattern: String
    public var replacement: String
    public var enabled: Bool
    public var continueMatching: Bool

    public init(
        id: UUID = UUID(),
        field: Field,
        pattern: String,
        replacement: String,
        enabled: Bool = true,
        continueMatching: Bool = true
    ) {
        self.id = id
        self.field = field
        self.pattern = pattern
        self.replacement = replacement
        self.enabled = enabled
        self.continueMatching = continueMatching
    }

    public func apply(to data: ScrobbleData) -> ScrobbleData? {
        guard enabled else { return nil }
        var edited = data

        func replace(_ value: String?) -> String? {
            guard let value else { return nil }
            return value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        switch field {
        case .artist:
            edited.artist = replace(edited.artist) ?? edited.artist
        case .track:
            edited.track = replace(edited.track) ?? edited.track
        case .album:
            edited.album = replace(edited.album)
        case .albumArtist:
            edited.albumArtist = replace(edited.albumArtist)
        }

        let trimmed = edited.trimmed()
        return trimmed == data ? nil : trimmed
    }
}

public struct MetadataPipelineResult: Sendable {
    public var scrobbleData: ScrobbleData
    public var blockedAction: BlockAction?
    public var blockedReason: String?
    public var editsApplied: Bool

    public init(
        scrobbleData: ScrobbleData,
        blockedAction: BlockAction? = nil,
        blockedReason: String? = nil,
        editsApplied: Bool = false
    ) {
        self.scrobbleData = scrobbleData
        self.blockedAction = blockedAction
        self.blockedReason = blockedReason
        self.editsApplied = editsApplied
    }
}

public struct MetadataPipeline: Sendable {
    public var simpleEdits: [SimpleEdit]
    public var regexEdits: [RegexEdit]
    public var blockRules: [BlockRule]
    public var extractFirstArtistAppIDs: Set<String>

    public init(
        simpleEdits: [SimpleEdit] = [],
        regexEdits: [RegexEdit] = [],
        blockRules: [BlockRule] = [],
        extractFirstArtistAppIDs: Set<String> = []
    ) {
        self.simpleEdits = simpleEdits
        self.regexEdits = regexEdits
        self.blockRules = blockRules
        self.extractFirstArtistAppIDs = extractFirstArtistAppIDs
    }

    public func preprocess(_ input: ScrobbleData) -> MetadataPipelineResult {
        var data = input.trimmed()
        var editsApplied = false

        if let blocked = blockRules.first(where: { $0.enabled && $0.matches(data) }) {
            return MetadataPipelineResult(
                scrobbleData: data,
                blockedAction: blocked.action,
                blockedReason: "\(blocked.field.rawValue) blocked",
                editsApplied: editsApplied
            )
        }

        for edit in simpleEdits where edit.enabled {
            if let edited = edit.apply(to: data) {
                data = edited
                editsApplied = true
                if !edit.continueMatching { break }
            }
        }

        for edit in regexEdits where edit.enabled {
            if let edited = edit.apply(to: data) {
                data = edited
                editsApplied = true
                if !edit.continueMatching { break }
            }
        }

        if let appID = data.appID, extractFirstArtistAppIDs.contains(appID) {
            let first = FirstArtistExtractor.extract(from: data.artist)
            if first != data.artist {
                data.albumArtist = data.albumArtist == data.artist ? first : data.albumArtist
                data.artist = first
                editsApplied = true
            }
        }

        return MetadataPipelineResult(scrobbleData: data.trimmed(), editsApplied: editsApplied)
    }
}

public enum FirstArtistExtractor {
    private static let delimiters = [
        " feat. ",
        " ft. ",
        " featuring ",
        " & ",
        " and ",
        ",",
        ";",
        "/",
        "、"
    ]

    public static func extract(from artist: String) -> String {
        let lower = artist.lowercased()
        let indexes = delimiters.compactMap { delimiter -> String.Index? in
            lower.range(of: delimiter)?.lowerBound
        }

        guard let firstIndex = indexes.min() else {
            return artist.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(artist[..<firstIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
