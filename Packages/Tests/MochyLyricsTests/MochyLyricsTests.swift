import XCTest
@testable import MochyLyrics

final class MochyLyricsTests: XCTestCase {
    func testTTMLAndEnhancedLRCParsers() {
        let ttml = """
        <tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
          <body><div>
            <p begin="00:01.00" end="00:03.50" ttm:agent="v1">
              <span begin="00:01.00" end="00:02.00">Hello</span>
              <span begin="00:02.10" end="00:03.50">World</span>
            </p>
            <p begin="00:04.00" end="00:06.00" ttm:agent="v2">
              <span begin="00:04.00" end="00:05.00" ttm:role="x-bg">(Echo)</span>
            </p>
          </div></body>
        </tt>
        """
        let doc = TTMLParser.parse(ttml, provider: "BetterLyrics")
        XCTAssertEqual(doc?.lines.count, 2)
        XCTAssertEqual(doc?.isWordTimed, true)
        XCTAssertEqual(doc?.hasDuet, true)
        XCTAssertEqual(doc?.hasBackgroundVocals, true)

        let lrc = "[00:12.50]<00:12.50>First <00:13.20>Word\n[00:15.00]Second Line"
        let lrcDoc = LRCParser.parse(lrc, provider: "LrcLib")
        XCTAssertEqual(lrcDoc?.lines.count, 2)
        XCTAssertEqual(lrcDoc?.isSynced, true)
        XCTAssertEqual(lrcDoc?.isWordTimed, true)
    }

    func testPickBestJapaneseDisambiguationAndWeightedScoring() {
        let chineseNetEase = LyricsDocument(
            sourceProvider: "NetEase",
            lines: [LyricsLine(startMs: 1000, text: "中文翻译歌词")],
            isSynced: true,
            isWordTimed: false,
            script: .han
        )
        let japaneseBetter = LyricsDocument(
            sourceProvider: "BetterLyrics",
            lines: [LyricsLine(startMs: 1000, text: "夢ならばどれほどよかったでしょう")],
            isSynced: true,
            isWordTimed: true,
            script: .kana
        )
        // Metadata written in Kanji ("夜に駆ける") -> Japan disambiguation rule must promote .kana over .han!
        let query = LyricsQuery(videoId: "v1", title: "夢見", artist: "米津玄師")
        let winner = LyricsHelper.pickBest(candidates: [chineseNetEase, japaneseBetter], query: query)
        XCTAssertEqual(winner?.sourceProvider, "BetterLyrics")
    }

    func testRomanizerTransformsCJKAndCyrillic() {
        let rom = LyricsRomanizer.romanize("東京")
        XCTAssertFalse(rom.isEmpty)
        XCTAssertNotEqual(rom, "東京")
    }
}
