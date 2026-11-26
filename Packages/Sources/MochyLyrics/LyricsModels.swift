import Foundation

public enum ScriptKind: String, Codable, Sendable, Equatable {
    case han
    case kana
    case hangul
    case devanagari
    case cyrillic
    case arabic
    case latin
    case unknown

    public var isCJK: Bool {
        self == .han || self == .kana || self == .hangul
    }
}

public struct LyricsWord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let startMs: Int
    public let endMs: Int
    public let text: String
    public let isBackground: Bool

    public init(
        startMs: Int,
        endMs: Int,
        text: String,
        isBackground: Bool = false
    ) {
        self.id = "\(startMs)-\(text.hashValue)"
        self.startMs = startMs
        self.endMs = max(startMs, endMs)
        self.text = text
        self.isBackground = isBackground
    }
}

public enum DuetAgent: String, Codable, Sendable, Equatable {
    case v1
    case v2
}

public struct LyricsLine: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String
    public let words: [LyricsWord]
    public let agent: DuetAgent?
    public let isBackground: Bool
    public var romanized: String?
    public var translated: String?

    public init(
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        words: [LyricsWord] = [],
        agent: DuetAgent? = nil,
        isBackground: Bool = false,
        romanized: String? = nil,
        translated: String? = nil
    ) {
        self.id = "\(startMs)-\(text)"
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
        self.agent = agent
        self.isBackground = isBackground
        self.romanized = romanized
        self.translated = translated
    }
}

public struct LyricsDocument: Codable, Sendable, Equatable {
    public let sourceProvider: String
    public let lines: [LyricsLine]
    public let isSynced: Bool
    public let isWordTimed: Bool
    public let hasDuet: Bool
    public let hasBackgroundVocals: Bool
    public let isSyllableSplit: Bool
    public let script: ScriptKind

    public var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    public static let cachedJSONPrefix = "MOCHY_LYR_JSON_V1:"

    /// Serializes the full `LyricsDocument` (including word-timings, duet agents, background vocals,
    /// romanization, and translations) so SQLite caching never degrades synced lyrics into plain text.
    public func encodeCachePayload() -> String {
        if let data = try? JSONEncoder().encode(self),
           let json = String(data: data, encoding: .utf8) {
            return Self.cachedJSONPrefix + json
        }
        return plainText
    }

    /// Restores a cached `LyricsDocument` losslessly from JSON payload, falling back cleanly to TTML / LRC parsing.
    public static func decodeCachePayload(_ raw: String, provider: String) -> LyricsDocument? {
        if raw.hasPrefix(cachedJSONPrefix) {
            let jsonPart = String(raw.dropFirst(cachedJSONPrefix.count))
            if let data = jsonPart.data(using: .utf8),
               let doc = try? JSONDecoder().decode(LyricsDocument.self, from: data),
               !doc.lines.isEmpty {
                return doc
            }
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<"),
           let ttmlDoc = TTMLParser.parse(raw, provider: provider) {
            return ttmlDoc
        }
        return LRCParser.parse(raw, provider: provider)
    }

    public init(
        sourceProvider: String,
        lines: [LyricsLine],
        isSynced: Bool,
        isWordTimed: Bool,
        hasDuet: Bool = false,
        hasBackgroundVocals: Bool = false,
        isSyllableSplit: Bool = false,
        script: ScriptKind = .unknown
    ) {
        self.sourceProvider = sourceProvider
        self.lines = lines
        self.isSynced = isSynced
        self.isWordTimed = isWordTimed
        self.hasDuet = hasDuet
        self.hasBackgroundVocals = hasBackgroundVocals
        self.isSyllableSplit = isSyllableSplit
        self.script = script
    }
}

public struct LyricsQuery: Sendable, Equatable {
    public let videoId: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Int
    public let isrc: String?
    public let localFileURL: URL?

    public init(
        videoId: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int = 0,
        isrc: String? = nil,
        localFileURL: URL? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isrc = isrc
        self.localFileURL = localFileURL
    }
}
