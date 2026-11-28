import XCTest
@testable import MochyCore
@testable import MochyInnerTube
@testable import MochyModules

final class MochyModulesTests: XCTestCase {
    func testFlacStreamInfoParserParses16BitAnd24BitHeaders() {
        var hdr16 = [UInt8](repeating: 0, count: 26)
        hdr16[0] = 0x66; hdr16[1] = 0x4C; hdr16[2] = 0x61; hdr16[3] = 0x43
        hdr16[18] = 0x0A; hdr16[19] = 0xC4; hdr16[20] = 0x42; hdr16[21] = 0xF0
        let info16 = FlacStreamInfoParser.parse(Data(hdr16))
        XCTAssertEqual(info16?.sampleRate, 44_100)
        XCTAssertEqual(info16?.channels, 2)
        XCTAssertEqual(info16?.bitsPerSample, 16)
        XCTAssertEqual(info16?.isHiRes, false)

        var hdr24 = [UInt8](repeating: 0, count: 26)
        hdr24[0] = 0x66; hdr24[1] = 0x4C; hdr24[2] = 0x61; hdr24[3] = 0x43
        hdr24[18] = 0x17; hdr24[19] = 0x70; hdr24[20] = 0x03; hdr24[21] = 0x70
        let info24 = FlacStreamInfoParser.parse(Data(hdr24))
        XCTAssertEqual(info24?.sampleRate, 96_000)
        XCTAssertEqual(info24?.bitsPerSample, 24)
        XCTAssertEqual(info24?.isHiRes, true)
        XCTAssertEqual(info24?.qualityBadge, "Hi-Res FLAC · 24-bit / 96 kHz")

        XCTAssertNil(FlacStreamInfoParser.parse(Data([0x00, 0x01, 0x02])))
    }

    func testModuleUrlGuardBlocksPrivateAndNonHttpURLs() {
        XCTAssertTrue(ModuleUrlGuard.isAllowedPublicURL(URL(string: "https://tracks.monochrome.st/track/1")!))
        XCTAssertFalse(ModuleUrlGuard.isAllowedPublicURL(URL(string: "http://127.0.0.1:8080/a")!))
        XCTAssertFalse(ModuleUrlGuard.isAllowedPublicURL(URL(string: "http://192.168.1.50/secret")!))
        XCTAssertFalse(ModuleUrlGuard.isAllowedPublicURL(URL(string: "http://localhost/admin")!))
        XCTAssertFalse(ModuleUrlGuard.isAllowedPublicURL(URL(string: "file:///etc/passwd")!))

        let clean = ModuleUrlGuard.sanitizeHeaders(["User-Agent": "Mochy", "Cookie": "SID=123", "Authorization": "Bearer X"])
        XCTAssertEqual(clean, ["User-Agent": "Mochy"])
    }

    func testMonochromeParseSearchCandidatesHandlesRealStreamerAndRelayPayloads() {
        let streamerPayload: [String: Any] = [
            "tracks": [
                [
                    "trackId": "tr_99123",
                    "title": "Blinding Lights",
                    "artistNames": ["The Weeknd", "Max Martin"],
                    "duration": 200_040,
                    "playable": true,
                    "isrc": "USUG11904206",
                ],
                [
                    "trackId": "tr_unplayable",
                    "title": "Blocked Track",
                    "artistNames": ["Blocked"],
                    "duration": 180_000,
                    "playable": false,
                ],
            ]
        ]
        let parsedStreamer = MonochromeModule.parseSearchCandidates(from: streamerPayload, kind: .streamer)
        XCTAssertEqual(parsedStreamer.count, 1)
        XCTAssertEqual(parsedStreamer[0].item, "tr_99123")
        XCTAssertEqual(parsedStreamer[0].artist, "The Weeknd, Max Martin")
        XCTAssertEqual(parsedStreamer[0].durationSeconds, 200)
        XCTAssertEqual(parsedStreamer[0].isrc, "USUG11904206")

        let relayPayload: [String: Any] = [
            "data": [
                [
                    "id": 7742,
                    "title": "Starboy",
                    "artist": "The Weeknd&Daft Punk",
                    "duration": 230,
                ]
            ]
        ]
        let parsedRelay = MonochromeModule.parseSearchCandidates(from: relayPayload, kind: .relay)
        XCTAssertEqual(parsedRelay.count, 1)
        XCTAssertEqual(parsedRelay[0].item, "7742")
        XCTAssertEqual(parsedRelay[0].artist, "The Weeknd, Daft Punk")
        XCTAssertEqual(parsedRelay[0].durationSeconds, 230)
    }

    func testJioSaavnParseSearchCandidatesUnescapesHTMLAndDetects320kbps() {
        let saavnPayload: [String: Any] = [
            "results": [
                [
                    "title": "Rock &amp; Roll &quot;Live&#039;s&quot;",
                    "more_info": [
                        "encrypted_media_url": "ENC_BASE64_TOKEN",
                        "duration": "214",
                        "320kbps": "true",
                        "artistMap": [
                            "primary_artists": [
                                ["name": "Arijit &amp; Friends"]
                            ]
                        ],
                    ],
                ]
            ]
        ]
        let parsed = JioSaavnModule.parseSearchCandidates(from: saavnPayload)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Rock & Roll \"Live's\"")
        XCTAssertEqual(parsed[0].artist, "Arijit & Friends")
        XCTAssertEqual(parsed[0].durationSeconds, 214)
        XCTAssertTrue(parsed[0].item.has320)
    }

    func testSourceModulesRouterRespectsPriorityAndLocalBypass() async throws {
        struct StubModule: MochyStreamModule {
            let id: String
            let displayName: String
            let supportsDownload = true
            let stream: ModuleStream?
            func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? { stream }
        }

        let slowOrNil = StubModule(id: "monochrome", displayName: "Mono", stream: nil)
        let winner = StubModule(
            id: "jiosaavn",
            displayName: "Saavn",
            stream: ModuleStream(
                url: URL(string: "https://aac.saavncdn.com/test.mp4")!,
                codec: "AAC",
                bitrate: 320_000,
                sourceId: "jiosaavn",
                sourceLabel: "JioSaavn",
                qualityBadge: "AAC 320 kbps"
            )
        )
        let router = SourceModulesRouter(modules: [slowOrNil, winner])

        let resolved = try await router.resolve(
            track: ModuleTrack(id: "t1", title: "Track", artist: "Artist"),
            sourceOrder: ["monochrome", "jiosaavn", "youtube"]
        )
        XCTAssertEqual(resolved.sourceId, "jiosaavn")

        let local = try await router.resolve(
            track: ModuleTrack(id: "LOCAL_1", title: "Local", artist: "Me", localFileURL: URL(fileURLWithPath: "/tmp/song.flac")),
            offlineMode: true
        )
        XCTAssertEqual(local.sourceId, "local")

        // When "youtube" is #1 and fails (or is marked failed), router MUST fall back to post-YouTube modules!
        let failingSessionCfg = URLSessionConfiguration.ephemeral
        failingSessionCfg.protocolClasses = [FailingYTProtocol.self]
        let failingSession = URLSession(configuration: failingSessionCfg)
        let failingYT = YTPlayerResolver(
            innerTube: InnerTubeClient(session: failingSession),
            session: failingSession
        )
        let monoFallback = StubModule(
            id: "monochrome",
            displayName: "Monochrome FLAC",
            stream: ModuleStream(
                url: URL(string: "https://tracks.monochrome.st/track/164377007696642048")!,
                codec: "FLAC",
                mimeType: "audio/flac",
                bitrate: 1_411_200,
                sourceId: "monochrome",
                sourceLabel: "Monochrome FLAC",
                qualityBadge: "FLAC · 16-bit / 44.1 kHz"
            )
        )
        let routerWithPostFallback = SourceModulesRouter(youtubeResolver: failingYT, modules: [monoFallback, slowOrNil])
        let postFallbackStream = try await routerWithPostFallback.resolve(
            track: ModuleTrack(id: "emMR03tG2CE", title: "Hãy Trao Cho Anh", artist: "Sơn Tùng M-TP"),
            sourceOrder: ["youtube", "monochrome", "jiosaavn"]
        )
        XCTAssertEqual(postFallbackStream.sourceId, "monochrome")
    }
}

private final class FailingYTProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
