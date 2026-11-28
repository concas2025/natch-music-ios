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

    func testCode128EncoderProducesValidModuleBitmap() {
        let text = "MFY2026-11"
        let modules = Code128Encoder.encode(text)
        // Expected width: Start(11) + 10 chars(110) + Checksum(11) + Stop(13) = 145 modules
        XCTAssertEqual(modules.count, 11 + text.count * 11 + 11 + 13)
        // Code 128B Start symbol (211214) starts with two dark bars, one light space
        XCTAssertEqual(Array(modules.prefix(3)), [true, true, false])
        // Stop symbol (2331112) ends with two dark bars
        XCTAssertEqual(Array(modules.suffix(2)), [true, true])
    }

    func testThumbnailURLUpgraderUpgradesGoogleAndYtimgURLs() {
        XCTAssertEqual(
            ThumbnailURLUpgrader.upgrade("https://lh3.googleusercontent.com/abc=w120-h120-l90-rj"),
            "https://lh3.googleusercontent.com/abc=w720-h720-l90-rj"
        )
        XCTAssertEqual(
            ThumbnailURLUpgrader.upgrade("https://yt3.ggpht.com/avatar=s60-c-k-c0x00ffffff-no-rj", size: 720),
            "https://yt3.ggpht.com/avatar=s720-c-k-c0x00ffffff-no-rj"
        )
        XCTAssertEqual(
            ThumbnailURLUpgrader.upgrade("https://i.ytimg.com/vi/abc123/mqdefault.jpg"),
            "https://i.ytimg.com/vi/abc123/hqdefault.jpg"
        )
        XCTAssertEqual(
            ThumbnailURLUpgrader.upgrade("file:///var/mobile/cover.jpg"),
            "file:///var/mobile/cover.jpg"
        )
        XCTAssertEqual(
            ThumbnailURLUpgrader.upgrade("https://example.com/art.png"),
            "https://example.com/art.png"
        )
    }

    @MainActor
    func testAppSettingsDefaultsAndV3Migration() {
        let freshSuite = "mochy.test.fresh.\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuite)!
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }

        let fresh = AppSettings(defaults: freshDefaults)
        XCTAssertEqual(fresh.seekbarStyle, .default)
        XCTAssertEqual(fresh.playerCoverStyle, .full)
        XCTAssertEqual(fresh.countryCode, "VN")
        XCTAssertEqual(fresh.languageCode, "vi")
        XCTAssertEqual(fresh.sourceOrder, ["youtube", "monochrome", "jiosaavn"])

        let legacySuite = "mochy.test.legacy.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }

        legacyDefaults.set(SeekbarStyle.wavy.rawValue, forKey: PreferenceKeys.seekbarStyle)
        legacyDefaults.set(PlayerCoverStyle.classic.rawValue, forKey: PreferenceKeys.playerCoverStyle)
        legacyDefaults.set(["monochrome", "jiosaavn", "youtube"], forKey: PreferenceKeys.sourceOrder)

        let migrated = AppSettings(defaults: legacyDefaults)
        XCTAssertEqual(migrated.seekbarStyle, .default)
        XCTAssertEqual(migrated.playerCoverStyle, .full)
        XCTAssertEqual(migrated.sourceOrder, ["youtube", "monochrome", "jiosaavn"])
    }
}
