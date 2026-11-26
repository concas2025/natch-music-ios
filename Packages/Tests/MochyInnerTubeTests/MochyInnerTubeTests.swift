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
    }

    func testPlayerResponseFlexibleStringAndIntDecoding() throws {
        let json = """
        {
          "playabilityStatus": { "status": "OK" },
          "streamingData": {
            "expiresInSeconds": 21540,
            "adaptiveFormats": [
              {
                "itag": 140,
                "url": "https://example.com/audio.mp4",
                "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"",
                "bitrate": 129800,
                "contentLength": "3500000",
                "audioQuality": "AUDIO_QUALITY_MEDIUM",
                "audioSampleRate": "44100",
                "audioChannels": 2
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PlayerResponse.self, from: json)
        let fmt = try XCTUnwrap(decoded.streamingData?.adaptiveFormats.first)
        XCTAssertEqual(fmt.contentLength, 3_500_000)
        XCTAssertEqual(fmt.audioSampleRate, 44_100)
        XCTAssertTrue(fmt.isAudio)
        XCTAssertTrue(fmt.isOriginal)
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

    func testStreamHeadersAndWebCreatorOrigin() {
        XCTAssertEqual(YouTubeClient.streamFallbackClients.first, .iOS)
        let webRemixIdx = YouTubeClient.streamFallbackClients.firstIndex(of: .webRemix) ?? -1
        let iPadIdx = YouTubeClient.streamFallbackClients.firstIndex(of: .iPadOS) ?? 99
        XCTAssertLessThan(iPadIdx, webRemixIdx)

        let iosHeaders = YTPlayerResolver.streamHeaders(for: .iOS, cookie: nil)
        XCTAssertNil(iosHeaders["Origin"])
        XCTAssertNil(iosHeaders["Referer"])

        XCTAssertEqual(YouTubeClient.webCreator.apiOrigin, "https://studio.youtube.com")
        let creatorHeaders = YTPlayerResolver.streamHeaders(for: .webCreator, cookie: "SAPISID=x")
        XCTAssertEqual(creatorHeaders["Origin"], "https://studio.youtube.com")
        XCTAssertEqual(creatorHeaders["Referer"], "https://studio.youtube.com/")
        XCTAssertEqual(creatorHeaders["Cookie"], "SAPISID=x")
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
