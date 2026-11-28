import XCTest
@testable import MochyCore
@testable import MochyInnerTube

final class MochyInnerTubeTests: XCTestCase {
    func testInnerTubeRequestHeadersForVisionOSAndWebRemix() async throws {
        let client = InnerTubeClient(
            locale: YouTubeLocale(gl: "VN", hl: "vi"),
            cookie: "SAPISID=test_sap_id; SID=abc",
            visitorData: "visitor-global",
            dataSyncId: "sync-123"
        )

        let visionCtx = YouTubeClient.visionOS.toContext(
            locale: YouTubeLocale(gl: "VN", hl: "vi"),
            visitorData: "visitor-vision",
            dataSyncId: "sync-123"
        )
        let visionReq = try await client.buildRequest(
            endpoint: "player",
            client: .visionOS,
            body: PlayerBody(context: visionCtx, videoId: "dQw4w9WgXcQ"),
            setLogin: true,
            visitorOverride: "visitor-vision",
            timestamp: 1_700_000_000
        )

        XCTAssertEqual(visionReq.url?.absoluteString, "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
        XCTAssertEqual(visionReq.value(forHTTPHeaderField: "X-YouTube-Client-Name"), "101")
        XCTAssertEqual(visionReq.value(forHTTPHeaderField: "X-Goog-Api-Format-Version"), "2")
        XCTAssertNil(visionReq.value(forHTTPHeaderField: "Origin"))
        XCTAssertNil(visionReq.value(forHTTPHeaderField: "Referer"))
        XCTAssertNil(visionReq.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(visionCtx.client.utcOffsetMinutes, 0)
        XCTAssertNil(visionCtx.user.onBehalfOfUser)

        let remixCtx = YouTubeClient.webRemix.toContext(
            locale: YouTubeLocale(gl: "VN", hl: "vi"),
            visitorData: "visitor-global",
            dataSyncId: "sync-123"
        )
        let remixReq = try await client.buildRequest(
            endpoint: "player",
            client: .webRemix,
            body: PlayerBody(context: remixCtx, videoId: "dQw4w9WgXcQ"),
            setLogin: true,
            visitorOverride: "visitor-global",
            timestamp: 1_700_000_000
        )

        XCTAssertEqual(remixReq.url?.absoluteString, "https://music.youtube.com/youtubei/v1/player?prettyPrint=false")
        XCTAssertEqual(remixReq.value(forHTTPHeaderField: "X-Origin"), "https://music.youtube.com")
        XCTAssertEqual(remixReq.value(forHTTPHeaderField: "Referer"), "https://music.youtube.com/")
        XCTAssertTrue(remixReq.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH 1700000000_") == true)
        XCTAssertEqual(remixCtx.user.onBehalfOfUser, "sync-123")

        // Native iOS/Android/AndroidVR clients must talk to www.youtube.com without browser X-Origin / Referer
        for native in [YouTubeClient.iOS, YouTubeClient.iPadOS, YouTubeClient.androidVR14332, YouTubeClient.mobile] {
            XCTAssertTrue(native.isNativeApp)
            XCTAssertEqual(native.apiOrigin, "https://www.youtube.com")
            let ctx = native.toContext(locale: YouTubeLocale(), visitorData: "v1", dataSyncId: nil)
            let req = try await client.buildRequest(
                endpoint: "player",
                client: native,
                body: PlayerBody(context: ctx, videoId: "emMR03tG2CE"),
                setLogin: false,
                visitorOverride: "v1",
                timestamp: 1_700_000_000
            )
            XCTAssertEqual(req.url?.host, "www.youtube.com")
            XCTAssertNil(req.value(forHTTPHeaderField: "X-Origin"))
            XCTAssertNil(req.value(forHTTPHeaderField: "Referer"))
        }

        // Embedded player context must carry video-specific watch embedUrl
        let embedCtx = YouTubeClient.tvHTML5SimplyEmbeddedPlayer.toContext(
            locale: YouTubeLocale(),
            visitorData: "v1",
            dataSyncId: nil,
            embedVideoId: "emMR03tG2CE"
        )
        XCTAssertEqual(embedCtx.thirdParty?.embedUrl, "https://www.youtube.com/watch?v=emMR03tG2CE")
    }

    func testPlayerResponseFlexibleStringAndIntDecoding() throws {
        // Real live VISIONOS payload shape: `expiresInSeconds` arrives as JSON String ("21540"),
        // plus mixed string/int numeric fields, missing optional videoDetails keys, and a malformed format entry.
        let visionOSLiveJSON = """
        {
          "playabilityStatus": { "status": "OK", "playableInEmbed": true },
          "playerConfig": {
            "audioConfig": { "perceptualLoudnessDb": -9.78 }
          },
          "videoDetails": {
            "videoId": "UH1Qb_tq7Wo",
            "title": "Hơn Cả Anh",
            "author": "VSTRA - Topic",
            "viewCount": "57153"
          },
          "streamingData": {
            "expiresInSeconds": "21540",
            "hlsManifestUrl": "https://manifest.googlevideo.com/api/manifest/hls_variant/example",
            "serverAbrStreamingUrl": "https://rr4---sn-42u-i5os7.googlevideo.com/videoplayback",
            "adaptiveFormats": [
              {
                "itag": "corrupted-entry"
              },
              {
                "itag": 140,
                "url": "https://rr4---sn-42u-i5os7.googlevideo.com/audio.mp4",
                "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"",
                "bitrate": 131209,
                "initRange": { "start": "0", "end": "767" },
                "indexRange": { "start": "768", "end": "1051" },
                "lastModified": "1795163399129633",
                "contentLength": "3353751",
                "audioQuality": "AUDIO_QUALITY_MEDIUM",
                "approxDurationMs": "207094",
                "audioSampleRate": "44100",
                "audioChannels": 2,
                "loudnessDb": 4.22
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PlayerResponse.self, from: visionOSLiveJSON)
        XCTAssertEqual(decoded.streamingData?.expiresInSeconds, 21_540)
        XCTAssertEqual(decoded.streamingData?.adaptiveFormats.count, 1)
        let fmt = try XCTUnwrap(decoded.streamingData?.adaptiveFormats.first)
        XCTAssertEqual(fmt.itag, 140)
        XCTAssertEqual(fmt.contentLength, 3_353_751)
        XCTAssertEqual(fmt.audioSampleRate, 44_100)
        XCTAssertEqual(fmt.lastModified, 1_795_163_399_129_633)
        XCTAssertEqual(fmt.initRange?.end, "767")
        XCTAssertTrue(fmt.isAudio)
        XCTAssertTrue(fmt.isOriginal)
        XCTAssertEqual(decoded.videoDetails?.channelId, "")
        XCTAssertEqual(decoded.videoDetails?.lengthSeconds, "0")
        XCTAssertEqual(decoded.playerConfig?.audioConfig?.perceptualLoudnessDb, -9.78)

        // Progressive-only response with integer expiresInSeconds and missing adaptiveFormats
        let progressiveOnlyJSON = """
        {
          "playabilityStatus": { "status": "OK" },
          "streamingData": {
            "expiresInSeconds": 21540,
            "formats": [
              {
                "itag": 18,
                "url": "https://example.com/prog18.mp4",
                "mimeType": "video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"",
                "bitrate": 500000,
                "width": 640,
                "height": 360
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let progDecoded = try JSONDecoder().decode(PlayerResponse.self, from: progressiveOnlyJSON)
        XCTAssertEqual(progDecoded.streamingData?.expiresInSeconds, 21_540)
        XCTAssertEqual(progDecoded.streamingData?.adaptiveFormats, [])
        XCTAssertEqual(progDecoded.streamingData?.formats?.first?.itag, 18)
    }

    func testFormatRankingExcludesWebMOnIOSAndAppendsProgressiveItag18Fallback() {
        let lowMp4 = PlayerResponse.StreamingData.Format(
            itag: 139, url: "https://ex/139", mimeType: "audio/mp4", bitrate: 48_000,
            audioQuality: "AUDIO_QUALITY_LOW", audioSampleRate: 22_050, audioChannels: 2
        )
        let highOpus = PlayerResponse.StreamingData.Format(
            itag: 251, url: "https://ex/251", mimeType: "audio/webm; codecs=\"opus\"", bitrate: 160_000,
            audioQuality: "AUDIO_QUALITY_MEDIUM", audioSampleRate: 48_000, audioChannels: 2
        )
        let premiumMp4 = PlayerResponse.StreamingData.Format(
            itag: 141, url: "https://ex/141", mimeType: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 256_000,
            audioQuality: "AUDIO_QUALITY_HIGH", audioSampleRate: 44_100, audioChannels: 2
        )
        let progressive18 = PlayerResponse.StreamingData.Format(
            itag: 18, url: "https://ex/18", mimeType: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
            bitrate: 500_000, width: 640, height: 360
        )
        let autoDubbed = PlayerResponse.StreamingData.Format(
            itag: 141, url: "https://ex/dub", mimeType: "audio/mp4", bitrate: 320_000,
            audioQuality: "AUDIO_QUALITY_HIGH", audioTrack: .init(displayName: "Spanish", id: "es", isAutoDubbed: true)
        )

        // iOS safe (`preferMp4 == true`): strictly excludes WebM (251) and appends progressive fallback (18)
        let iosRanked = YTPlayerResolver.selectCandidateFormats(
            from: [lowMp4, highOpus, autoDubbed, premiumMp4, progressive18],
            quality: .high,
            preferMp4: true
        )
        XCTAssertEqual(iosRanked.map(\.itag), [141, 139, 18])

        // Non-iOS (`preferMp4 == false`): allows Opus (251)
        let anyRanked = YTPlayerResolver.selectCandidateFormats(
            from: [lowMp4, highOpus, autoDubbed, premiumMp4],
            quality: .high,
            preferMp4: false
        )
        XCTAssertEqual(anyRanked.map(\.itag), [141, 251, 139])

        let lowRanked = YTPlayerResolver.selectCandidateFormats(
            from: [lowMp4, highOpus, premiumMp4],
            quality: .low,
            preferMp4: true
        )
        XCTAssertEqual(lowRanked.map(\.itag), [139])
    }

    func testValidateStreamURLChecksLastByteRangeAndPast1MiBProbeRejects416() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let capturedRanges = LockedBox<[String]>([])
        MockURLProtocol.handler = { request in
            capturedRanges.withLock { $0.append(request.value(forHTTPHeaderField: "Range") ?? "") }
            let urlStr = request.url?.absoluteString ?? ""
            if urlStr.contains("cutoff403") {
                return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
            }
            if urlStr.contains("cutoff416") {
                return (HTTPURLResponse(url: request.url!, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
            }
            let headers = ["Content-Range": "bytes 1150000-1150001/4194304"]
            return (HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!, Data([0x01, 0x02]))
        }

        let cutoffOk = await YTPlayerResolver.validateStreamURL(
            url: URL(string: "https://cdn.example.com/cutoff403")!,
            client: .visionOS,
            contentLength: 5_000_000,
            cookie: nil,
            session: session
        )
        XCTAssertFalse(cutoffOk)

        // When contentLength == nil, probe MUST check bytes=1150000-1150001 and REJECT HTTP 416!
        let rejected416 = await YTPlayerResolver.validateStreamURL(
            url: URL(string: "https://cdn.example.com/cutoff416")!,
            client: .iOS,
            contentLength: nil,
            cookie: nil,
            session: session
        )
        XCTAssertFalse(rejected416)

        let validPast1MiB = await YTPlayerResolver.validateStreamURL(
            url: URL(string: "https://cdn.example.com/ok")!,
            client: .iOS,
            contentLength: nil,
            cookie: nil,
            session: session
        )
        XCTAssertTrue(validPast1MiB)
        XCTAssertEqual(
            capturedRanges.value,
            ["bytes=4999999-4999999", "bytes=1150000-1150001", "bytes=1150000-1150001"]
        )
    }

    func testStreamHeadersVisionOSFirstAndPrioritizedItag18() {
        XCTAssertEqual(YouTubeClient.streamFallbackClients.first, .visionOS)
        let visionIdx = YouTubeClient.streamFallbackClients.firstIndex(of: .visionOS) ?? 99
        let webRemixIdx = YouTubeClient.streamFallbackClients.firstIndex(of: .webRemix) ?? 99
        let iPadIdx = YouTubeClient.streamFallbackClients.firstIndex(of: .iPadOS) ?? -1
        XCTAssertLessThan(visionIdx, webRemixIdx)
        XCTAssertLessThan(webRemixIdx, iPadIdx)

        // Ensure progressive itag 18 is NEVER dropped when 4 adaptive formats precede it
        let fourAdaptive = [141, 140, 139, 256].map {
            PlayerResponse.StreamingData.Format(itag: $0, url: "https://ex/\($0)", mimeType: "audio/mp4", bitrate: $0 * 1000)
        }
        let itag18 = PlayerResponse.StreamingData.Format(itag: 18, url: "https://ex/18", mimeType: "video/mp4", bitrate: 500_000, width: 640, height: 360)
        let ranked = YTPlayerResolver.selectCandidateFormats(from: fourAdaptive + [itag18], quality: .high, preferMp4: true)
        let probed = YTPlayerResolver.prioritizedProbeCandidates(from: ranked)
        XCTAssertTrue(probed.contains(where: { $0.itag == 18 }))

        let iosHeaders = YTPlayerResolver.streamHeaders(for: .iOS, cookie: nil)
        XCTAssertNil(iosHeaders["Origin"])
        XCTAssertNil(iosHeaders["Referer"])

        XCTAssertEqual(YouTubeClient.webCreator.apiOrigin, "https://studio.youtube.com")
        let creatorHeaders = YTPlayerResolver.streamHeaders(for: .webCreator, cookie: "SAPISID=x")
        XCTAssertEqual(creatorHeaders["Origin"], "https://studio.youtube.com")
        XCTAssertEqual(creatorHeaders["Referer"], "https://studio.youtube.com/")
        XCTAssertEqual(creatorHeaders["Cookie"], "SAPISID=x")
    }

    func testValidateAndMeasureFailsOverAcrossMnMirrorsOnTimeout() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            let host = request.url?.host ?? ""
            if host.contains("sn-dead") {
                throw URLError(.timedOut)
            }
            let headers = ["Content-Range": "bytes 3978900-3978900/3978901"]
            return (HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!, Data([0xAA]))
        }

        let deadEdgeURL = URL(string: "https://rr5---sn-dead.googlevideo.com/videoplayback?mn=sn-dead,sn-healthy&clen=3978901")!
        let result = await YTPlayerResolver.validateAndMeasureStreamURL(
            url: deadEdgeURL,
            client: .visionOS,
            contentLength: YTPlayerResolver.extractClenParam(from: deadEdgeURL),
            cookie: nil,
            session: session
        )
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.validatedURL.host, "rr5---sn-healthy.googlevideo.com")
        XCTAssertEqual(result.measuredLength, 3_978_901)
    }

    func testResolverReportsPerClientDiagnosticReasonsWhenAllClientsFail() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            let body = """
            {"playabilityStatus":{"status":"UNPLAYABLE","reason":"Video unavailable in region"}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
        }

        let resolver = YTPlayerResolver(
            innerTube: InnerTubeClient(visitorData: "v-test", session: session),
            session: session
        )
        do {
            _ = try await resolver.resolveStream(videoId: "blocked_vid")
            XCTFail("Expected noPlayableStream error")
        } catch let err as YTPlayerResolverError {
            let desc = err.errorDescription ?? ""
            XCTAssertTrue(desc.contains("visionOS: UNPLAYABLE (Video unavailable in region)"), "Actual error: \(desc)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateStreamURLHandlesTiny416VsCutoff416() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.handler = { request in
            let urlStr = request.url?.absoluteString ?? ""
            if urlStr.contains("tiny") {
                let hdrs = ["Content-Range": "bytes */420000"]
                return (HTTPURLResponse(url: request.url!, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: hdrs)!, Data())
            }
            let hdrs = ["Content-Range": "bytes */850000"]
            return (HTTPURLResponse(url: request.url!, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: hdrs)!, Data())
        }

        let tinyOk = await YTPlayerResolver.validateStreamURL(
            url: URL(string: "https://cdn.example.com/tiny")!,
            client: .iOS,
            contentLength: nil,
            cookie: nil,
            session: session
        )
        XCTAssertTrue(tinyOk)

        let cutoffRejected = await YTPlayerResolver.validateStreamURL(
            url: URL(string: "https://cdn.example.com/cutoff850")!,
            client: .iOS,
            contentLength: nil,
            cookie: nil,
            session: session
        )
        XCTAssertFalse(cutoffRejected)
    }

    func testBundledEjsSolverLoadsInJavaScriptCore() throws {
        let ctx = try EjsSolver.createSolverContext()
        let typeofJsc = ctx.evaluateScript("typeof jsc")?.toString()
        XCTAssertEqual(typeofJsc, "function")
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ value: T) { self.storage = value }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
