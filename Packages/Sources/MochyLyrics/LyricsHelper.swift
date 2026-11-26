import Foundation
import MochyInnerTube

/// Dominant Unicode script detector ported from Mochy's `LyricsHelper`.
public enum ScriptDetector {
    public static func detect(_ text: String) -> ScriptKind {
        var counts: [ScriptKind: Int] = [:]
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let kind: ScriptKind?
            switch v {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF:
                kind = .kana
            case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                kind = .han
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                kind = .hangul
            case 0x0900...0x097F:
                kind = .devanagari
            case 0x0400...0x04FF:
                kind = .cyrillic
            case 0x0600...0x06FF:
                kind = .arabic
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                kind = .latin
            default:
                kind = nil
            }
            if let kind {
                counts[kind, default: 0] += 1
            }
        }

        // Any presence of Kana unambiguously identifies Japanese even when Kanji (Han) dominates count.
        if (counts[.kana] ?? 0) > 0 {
            return .kana
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .unknown
    }
}

/// Orchestrates parallel lyrics fetching + exact weighted language/feature grading (`pickBest`).
public actor LyricsHelper {
    private static let providerTimeoutNs: UInt64 = 35_000_000_000
    private static let chineseProviders: Set<String> = ["KuGou", "NetEase", "QQMusic"]

    private let providers: [any LyricsProvider]
    private let lastResortProvider: any LyricsProvider

    public init(
        providers: [any LyricsProvider] = [
            LocalSidecarLyricsProvider(),
            BetterLyricsProvider(),
            UnisonProvider(),
            YouLyPlusProvider(),
            LrcRedProvider(),
            SimpMusicProvider(),
            LrcLibProvider(),
            NetEaseLyricsProvider(),
            KuGouLyricsProvider(),
        ],
        lastResortProvider: any LyricsProvider = YouTubeCaptionsLyricsProvider()
    ) {
        self.providers = providers
        self.lastResortProvider = lastResortProvider
    }

    public func fetchLyrics(query: LyricsQuery, orderOverride: Bool = false) async -> LyricsDocument? {
        if let local = await LocalSidecarLyricsProvider().fetch(query: query) {
            return local
        }

        let candidates = await withTaskGroup(of: (Int, LyricsDocument?).self) { group in
            for (idx, provider) in providers.enumerated() where provider.name != "LocalFile" {
                group.addTask {
                    let doc = await provider.fetch(query: query)
                    return (idx, doc)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.providerTimeoutNs)
                return (-1, nil)
            }

            var collected: [(Int, LyricsDocument)] = []
            for await (idx, doc) in group {
                if idx == -1 {
                    group.cancelAll()
                    break
                }
                if let doc {
                    collected.append((idx, doc))
                }
                if collected.count >= providers.count - 1 {
                    group.cancelAll()
                    break
                }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let order = providers.map(\.name)
        if let best = Self.pickBest(candidates: candidates, query: query, providerOrder: order, orderOverride: orderOverride) {
            return best
        }

        return await lastResortProvider.fetch(query: query)
    }

    /// Exact port of Mochy's `LyricsHelper.pickBest`:
    /// Score = scriptScore * 1_000_000 + timedScore * 100_000 + hindiBonus + featureScore * 1_000 + orderScore
    public static func pickBest(
        candidates: [LyricsDocument],
        query: LyricsQuery,
        providerOrder: [String] = ["LocalFile", "BetterLyrics", "Unison", "YouLyPlus", "LrcRed", "SimpMusic", "LrcLib", "NetEase", "QQMusic", "KuGou"],
        orderOverride: Bool = false
    ) -> LyricsDocument? {
        guard !candidates.isEmpty else { return nil }

        let metaText = [query.title, query.artist, query.album ?? ""].joined(separator: " ")
        var referenceScript = ScriptDetector.detect(metaText)

        // Japan-China disambiguation rule: if metadata uses Hanzi/Kanji and ANY candidate contains Kana, treat track as Japanese.
        if referenceScript == .han && candidates.contains(where: { $0.script == .kana }) {
            referenceScript = .kana
        }
        // When metadata is Romanized/Latin (e.g. anime or J-pop English titles) and candidates include non-Latin lyrics without Latin match, keep neutral if mixed.
        let chineseSong = (referenceScript == .han)

        let eligible = candidates.filter { doc in
            if chineseProviders.contains(doc.sourceProvider) {
                return chineseSong || (doc.isWordTimed && doc.script == referenceScript)
            }
            return true
        }
        let pool = eligible.isEmpty ? candidates : eligible

        return pool.max { lhs, rhs in
            grade(lhs, referenceScript: referenceScript, providerOrder: providerOrder, orderOverride: orderOverride)
                < grade(rhs, referenceScript: referenceScript, providerOrder: providerOrder, orderOverride: orderOverride)
        }
    }

    public static func grade(
        _ doc: LyricsDocument,
        referenceScript: ScriptKind,
        providerOrder: [String],
        orderOverride: Bool
    ) -> Int {
        let scriptScore: Int
        if referenceScript == .unknown || doc.script == .unknown {
            scriptScore = 1
        } else if doc.script == referenceScript {
            scriptScore = 3
        } else if doc.script.isCJK && referenceScript.isCJK {
            scriptScore = 2
        } else {
            scriptScore = 0
        }

        let timedScore = doc.isSynced ? 1 : 0
        let hindiBonus = (referenceScript == .devanagari && doc.script == .devanagari) ? 10_000 : 0
        let featureScore =
            (doc.hasDuet ? 4 : 0) +
            ((doc.isWordTimed && !doc.isSyllableSplit) ? 3 : 0) +
            (doc.hasBackgroundVocals ? 2 : 0)

        let rankIdx = providerOrder.firstIndex(of: doc.sourceProvider) ?? providerOrder.count
        let reverseRank = max(0, providerOrder.count - rankIdx)
        let orderScore = orderOverride ? (reverseRank * 50_000) : reverseRank

        return scriptScore * 1_000_000
            + timedScore * 100_000
            + (orderOverride ? orderScore : hindiBonus)
            + featureScore * 1_000
            + (orderOverride ? hindiBonus : orderScore)
    }
}
