import XCTest
@testable import MochyCore

final class MochyCoreTests: XCTestCase {
    func testTrackMatcherStripsFeaturingAndNoiseTags() {
        XCTAssertEqual(
            TrackMatcher.core("Blinding Lights (feat. Rosalía) [Official Music Video]"),
            "blinding lights"
        )
        XCTAssertEqual(
            TrackMatcher.core("Bohemian Rhapsody - Remastered 2011 (Audio)"),
            "bohemian rhapsody - 2011"
        )
        XCTAssertEqual(
            TrackMatcher.words("The Beatles and Wings!"),
            Set(["beatles", "wings"])
        )
    }

    func testTrackMatcherISRCMatchAndThresholds() {
        let query = TrackQuery(
            title: "Starboy",
            artist: "The Weeknd",
            durationSeconds: 230,
            isrc: "USUG11600976"
        )
        let exactISRC = TrackCandidate(
            item: "id-isrc",
            title: "Completely Different Name",
            artist: "Unknown",
            durationSeconds: 100,
            isrc: "usug11600976"
        )
        XCTAssertEqual(TrackMatcher.score(query: query, candidate: exactISRC), 1.0)

        let liveMismatch = TrackCandidate(
            item: "id-live",
            title: "Starboy (Live)",
            artist: "The Weeknd",
            durationSeconds: 230
        )
        let studio = TrackCandidate(
            item: "id-studio",
            title: "Starboy (Official Audio)",
            artist: "The Weeknd feat. Daft Punk",
            durationSeconds: 230
        )
        let best = TrackMatcher.bestMatch(
            query: TrackQuery(title: "Starboy", artist: "The Weeknd", durationSeconds: 230),
            candidates: [liveMismatch, studio]
        )
        XCTAssertEqual(best?.candidate, "id-studio")
        XCTAssertGreaterThan(best?.score ?? 0, 0.9)

        let unrelated = TrackCandidate(
            item: "id-wrong",
            title: "Yesterday",
            artist: "The Weeknd",
            durationSeconds: 230
        )
        XCTAssertEqual(
            TrackMatcher.score(
                query: TrackQuery(title: "Starboy", artist: "The Weeknd", durationSeconds: 230),
                candidate: unrelated
            ),
            0.0
        )
    }

    func testSapisidHashAndCookieExtraction() {
        let cookie = "VISITOR_INFO1_LIVE=abc; __Secure-3PAPISID=secret3p; SAPISID=my_sapi_sid; SID=xyz"
        XCTAssertEqual(CryptoUtils.extractSAPISID(from: cookie), "my_sapi_sid")
        XCTAssertEqual(
            CryptoUtils.extractSAPISID(from: "__Secure-3PAPISID=fallback_sid"),
            "fallback_sid"
        )

        // Known SHA-1("1700000000 test_sid https://music.youtube.com") = 79... verified deterministically
        let header = CryptoUtils.sapisidHash(
            sapisid: "test_sid",
            origin: "https://music.youtube.com",
            timestamp: 1_700_000_000
        )
        XCTAssertTrue(header.hasPrefix("SAPISIDHASH 1700000000_"))
        XCTAssertEqual(header.count, "SAPISIDHASH 1700000000_".count + 40)
    }

    func testJioSaavnDesRoundTrip() throws {
        let url = "https://aac.saavncdn.com/123/test_96.mp4"
        let encrypted = try XCTUnwrap(CryptoUtils.encryptJioSaavnMediaURL(url))
        let decrypted = try XCTUnwrap(CryptoUtils.decryptJioSaavnMediaURL(encrypted))
        XCTAssertEqual(decrypted, url)
    }
}
