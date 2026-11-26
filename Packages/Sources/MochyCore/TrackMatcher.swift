import Foundation

public struct TrackQuery: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let durationSeconds: Int?
    public let isrc: String?

    public init(
        title: String,
        artist: String,
        durationSeconds: Int? = nil,
        isrc: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }
}

public struct TrackCandidate<T> {
    public let item: T
    public let title: String
    public let artist: String
    public let durationSeconds: Int?
    public let isrc: String?

    public init(
        item: T,
        title: String,
        artist: String,
        durationSeconds: Int? = nil,
        isrc: String? = nil
    ) {
        self.item = item
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }
}

/// Faithful Swift port of Mochy Music's `TrackMatcher.kt` weighted metadata similarity matcher.
public enum TrackMatcher {
    private static let parenFeatRegex = try! NSRegularExpression(
        pattern: #"\s*[\(\[](?:feat\.?|ft\.?|featuring|with|prod\.?)[^\)\]]*[\)\]]"#,
        options: [.caseInsensitive]
    )
    private static let trailingFeatRegex = try! NSRegularExpression(
        pattern: #"\s+(?:feat\.?|ft\.?|featuring|with|prod\.?)\s+.*$"#,
        options: [.caseInsensitive]
    )
    private static let parenNoiseRegex = try! NSRegularExpression(
        pattern: #"\s*[\(\[](?:[^\)\]]*\b(?:remaster(?:ed)?|official|video|audio|lyrics?|visualizer|mv|explicit|clean|hd|4k)\b[^\)\]]*)[\)\]]"#,
        options: [.caseInsensitive]
    )
    private static let inlineNoiseRegex = try! NSRegularExpression(
        pattern: #"\b(?:remastered|official|video|audio|lyrics|visualizer|mv|explicit|clean)\b"#,
        options: [.caseInsensitive]
    )
    private static let nonWordRegex = try! NSRegularExpression(
        pattern: #"[^\p{L}\p{N}]+"#,
        options: []
    )
    private static let whitespaceRegex = try! NSRegularExpression(
        pattern: #"\s+"#,
        options: []
    )

    private static let stopWords: Set<String> = ["the", "and"]
    private static let versionKeywords: [String] = [
        "live", "acoustic", "remix", "instrumental", "karaoke",
        "sped up", "slowed", "radio edit", "extended", "demo", "cover"
    ]

    public static func core(_ raw: String) -> String {
        var text = raw.lowercased()
        text = replace(parenFeatRegex, in: text, with: " ")
        text = replace(trailingFeatRegex, in: text, with: " ")
        text = replace(parenNoiseRegex, in: text, with: " ")
        text = replace(inlineNoiseRegex, in: text, with: " ")
        text = replace(whitespaceRegex, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func words(_ raw: String) -> Set<String> {
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let spaced = nonWordRegex.stringByReplacingMatches(in: raw.lowercased(), range: nsRange, withTemplate: " ")
        let tokens = spaced
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return Set(tokens)
    }

    public static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0.0 : Double(intersection) / Double(union)
    }

    public static func versionTags(_ raw: String) -> Set<String> {
        let lower = raw.lowercased()
        return Set(versionKeywords.filter { lower.contains($0) })
    }

    public static func score<T>(query: TrackQuery, candidate: TrackCandidate<T>) -> Double {
        if let qIsrc = query.isrc?.trimmingCharacters(in: .whitespacesAndNewlines),
           !qIsrc.isEmpty,
           let cIsrc = candidate.isrc?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cIsrc.isEmpty,
           qIsrc.caseInsensitiveCompare(cIsrc) == .orderedSame {
            return 1.0
        }

        let qCoreTitle = core(query.title)
        let cCoreTitle = core(candidate.title)
        let qTitleWords = words(qCoreTitle)
        let cTitleWords = words(cCoreTitle)

        var titleScore = jaccard(qTitleWords, cTitleWords)
        if !qCoreTitle.isEmpty && !cCoreTitle.isEmpty {
            if qCoreTitle == cCoreTitle {
                titleScore = 1.0
            } else if qCoreTitle.contains(cCoreTitle) || cCoreTitle.contains(qCoreTitle) {
                titleScore = max(titleScore, 0.85)
            }
        }

        let qCoreArtist = core(query.artist)
        let cCoreArtist = core(candidate.artist)
        var artistScore = jaccard(words(qCoreArtist), words(cCoreArtist))
        if !qCoreArtist.isEmpty && !cCoreArtist.isEmpty {
            if qCoreArtist == cCoreArtist {
                artistScore = 1.0
            } else if qCoreArtist.contains(cCoreArtist) || cCoreArtist.contains(qCoreArtist) {
                artistScore = max(artistScore, 0.85)
            }
        }

        if titleScore < 0.55 || artistScore < 0.50 {
            return 0.0
        }

        let durationScore: Double
        if let qDur = query.durationSeconds, let cDur = candidate.durationSeconds, qDur > 0, cDur > 0 {
            durationScore = max(0.0, 1.0 - Double(abs(qDur - cDur)) / 15.0)
        } else {
            durationScore = 0.7
        }

        let qVersions = versionTags(query.title)
        let cVersions = versionTags(candidate.title)
        let versionMismatch = qVersions != cVersions

        let raw = 0.5 * titleScore + 0.3 * artistScore + 0.2 * durationScore - (versionMismatch ? 0.25 : 0.0)
        return min(1.0, max(0.0, raw))
    }

    public static func bestMatch<T>(
        query: TrackQuery,
        candidates: [TrackCandidate<T>],
        threshold: Double = 0.70
    ) -> (candidate: T, score: Double)? {
        var best: (candidate: T, score: Double)?
        for candidate in candidates {
            let s = score(query: query, candidate: candidate)
            if s >= threshold, best == nil || s > best!.score {
                best = (candidate.item, s)
            }
        }
        return best
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
