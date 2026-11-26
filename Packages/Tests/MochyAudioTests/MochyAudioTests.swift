import Foundation
import XCTest
@testable import MochyAudio

final class MochyAudioTests: XCTestCase {
    func testWebMOpusDemuxerExtractsOpusPackets() {
        func elem(_ id: [UInt8], _ payload: [UInt8]) -> [UInt8] {
            var res = id
            let size = payload.count
            precondition(size < 127)
            res.append(UInt8(0x80 | size))
            res.append(contentsOf: payload)
            return res
        }
        let codecId = elem([0x86], Array("A_OPUS".utf8))
        let trackNum = elem([0xD7], [0x01])
        let trackEntry = elem([0xAE], trackNum + codecId)
        let tracks = elem([0x16, 0x54, 0xAE, 0x6B], trackEntry)

        let timecode = elem([0xE7], [0x03, 0xE8]) // 1000ms
        let opusPayload: [UInt8] = [0xFC, 0x01, 0x02, 0x03, 0x04]
        let simpleBlock = elem([0xA3], [0x81, 0x00, 0x14, 0x80] + opusPayload)
        let cluster = elem([0x1F, 0x43, 0xB6, 0x75], timecode + simpleBlock)
        let segment = elem([0x18, 0x53, 0x80, 0x67], tracks + cluster)

        let parsed = WebMOpusDemuxer.parse(data: Data(segment))
        XCTAssertEqual(parsed?.packets.count, 1)
        XCTAssertEqual(parsed?.packets.first?.timestampMs, 1020)
        XCTAssertEqual(parsed?.packets.first?.data, Data(opusPayload))
    }

    func testChunkRangeCacheStoresReadsEvictsAndUsesRealFileExtensions() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mochy_cache_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = ChunkRangeCache(directory: tmp, maxCacheBytes: 100)
        try await cache.storeChunk(mediaId: "m1", chunkIndex: 0, data: Data(repeating: 0x11, count: 70))
        let read1 = await cache.readChunk(mediaId: "m1", chunkIndex: 0)
        XCTAssertEqual(read1?.count, 70)

        try await cache.storeChunk(mediaId: "m2", chunkIndex: 0, data: Data(repeating: 0x22, count: 70))
        let evicted = await cache.readChunk(mediaId: "m1", chunkIndex: 0)
        let kept = await cache.readChunk(mediaId: "m2", chunkIndex: 0)
        XCTAssertNil(evicted)
        XCTAssertEqual(kept?.count, 70)

        let flacCache = ChunkRangeCache(directory: tmp.appendingPathComponent("ext"), maxCacheBytes: 1024 * 1024)
        try await flacCache.markCompleted(mediaId: "track_hi_res", fileExtension: "flac", fullFileData: Data([0x66, 0x4C, 0x61, 0x43]))
        let isCached = await flacCache.isFullyCached(mediaId: "track_hi_res")
        let fullURL = await flacCache.completeFileURL(mediaId: "track_hi_res")
        XCTAssertTrue(isCached)
        XCTAssertEqual(fullURL.pathExtension, "flac")
    }

    func testAll19CrossmixStylesAndPlanner() {
        XCTAssertEqual(CrossmixStyle.allCases.count, 19)
        for style in CrossmixStyle.allCases {
            let pair = style.deckParameters(progress: 0.5, bpm: 124)
            XCTAssertTrue(pair.outgoing.crossmixGain.isFinite)
            XCTAssertTrue(pair.incoming.crossmixGain.isFinite)
        }

        let pOut = TrackAudioProfile(bpm: 122, averageRMS: 0.25, introSeconds: 0, outroStartSeconds: 180)
        let pIn = TrackAudioProfile(bpm: 124, averageRMS: 0.24, introSeconds: 0, outroStartSeconds: 190)
        let plan = CrossmixPlanner.plan(from: pOut, to: pIn)
        XCTAssertEqual(plan.style, .bassSwap)
    }

    func testMP4DurationNormalizerZeroesV0AndV1FragmentedHeadersAndGuards2xDuration() {
        func makeBox(_ type: String, payload: [UInt8]) -> [UInt8] {
            let len = UInt32(8 + payload.count)
            var out: [UInt8] = [
                UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF),
            ]
            out.append(contentsOf: type.utf8)
            out.append(contentsOf: payload)
            return out
        }

        // Version 0 fragmented MP4 (mvhd + trak(tkhd + mdia(mdhd)) + mvex)
        var mvhdV0 = [UInt8](repeating: 0, count: 24)
        mvhdV0[16] = 0x00; mvhdV0[17] = 0x05; mvhdV0[18] = 0x46; mvhdV0[19] = 0x00
        var tkhdV0 = [UInt8](repeating: 0, count: 28)
        tkhdV0[20] = 0x00; tkhdV0[21] = 0x05; tkhdV0[22] = 0x46; tkhdV0[23] = 0x00
        var mdhdV0 = [UInt8](repeating: 0, count: 24)
        mdhdV0[16] = 0x00; mdhdV0[17] = 0x93; mdhdV0[18] = 0xA8; mdhdV0[19] = 0x00

        let mdiaV0 = makeBox("mdia", payload: makeBox("mdhd", payload: mdhdV0))
        let trakV0 = makeBox("trak", payload: makeBox("tkhd", payload: tkhdV0) + mdiaV0)
        let mvex = makeBox("mvex", payload: [0, 0, 0, 0])
        let ftyp = makeBox("ftyp", payload: Array("iso5\0\0\0\0".utf8))
        let fmp4V0 = Data(ftyp + makeBox("moov", payload: makeBox("mvhd", payload: mvhdV0) + trakV0 + mvex))

        let normV0 = MP4DurationNormalizer.normalizeFragmentedMp4Header(fmp4V0)
        XCTAssertTrue(normV0.patched)
        XCTAssertEqual(normV0.data.count, fmp4V0.count)
        // Re-running must find zero non-zero duration fields left
        XCTAssertFalse(MP4DurationNormalizer.normalizeFragmentedMp4Header(normV0.data).patched)

        // Version 1 64-bit mvhd + tkhd
        var mvhdV1 = [UInt8](repeating: 0, count: 36)
        mvhdV1[0] = 1
        mvhdV1[24] = 0x00; mvhdV1[31] = 0x7F
        var tkhdV1 = [UInt8](repeating: 0, count: 40)
        tkhdV1[0] = 1
        tkhdV1[28] = 0x00; tkhdV1[35] = 0x7F
        let fmp4V1 = Data(makeBox("moov", payload: makeBox("mvhd", payload: mvhdV1) + makeBox("trak", payload: makeBox("tkhd", payload: tkhdV1)) + mvex))
        let normV1 = MP4DurationNormalizer.normalizeFragmentedMp4Header(fmp4V1)
        XCTAssertTrue(normV1.patched)
        XCTAssertEqual(normV1.data.count, fmp4V1.count)
        XCTAssertFalse(MP4DurationNormalizer.normalizeFragmentedMp4Header(normV1.data).patched)

        // Progressive non-fragmented MP4 (without mvex) must NEVER be modified
        let progressive = Data(makeBox("moov", payload: makeBox("mvhd", payload: mvhdV0)))
        XCTAssertFalse(MP4DurationNormalizer.normalizeFragmentedMp4Header(progressive).patched)

        // 2x phantom duration guard
        XCTAssertEqual(MP4DurationNormalizer.resolveEffectiveDuration(reported: 420.0, known: 210.0), 210.0)
        XCTAssertEqual(MP4DurationNormalizer.resolveEffectiveDuration(reported: 211.5, known: 210.0), 211.5)
        XCTAssertEqual(MP4DurationNormalizer.resolveEffectiveDuration(reported: .nan, known: 185.0), 185.0)
    }

    func testSpectrumAnalyzerDetects1000HzSinePeak() {
        let sampleRate = 48_000.0
        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        let samples = (0..<2048).map { i in
            sinf(Float(i) * 2.0 * .pi * 1000.0 / Float(sampleRate)) * 0.9
        }
        samples.withUnsafeBufferPointer { buf in
            analyzer.consume(samples: buf.baseAddress!, count: buf.count)
            analyzer.consume(samples: buf.baseAddress!, count: buf.count)
        }
        let snap = analyzer.snapshot()
        XCTAssertEqual(snap.bins.count, 32)
        // 1 kHz sits in the mid-frequency bins (~14...20); sub-bass bins (0...2) should be much lower
        let midPeak = snap.bins[14...21].max() ?? 0
        let subBass = snap.bins[0...2].max() ?? 0
        XCTAssertGreaterThan(midPeak, 0.5)
        XCTAssertGreaterThan(midPeak, subBass + 0.25)
    }

    func testLocalAudioProxyServesHeadRangeAndRefreshesOn403AndBuildsFailoverURLs() async throws {
        // 1. Verify YouTube mn= failover URL builder
        let ytURL = URL(string: "https://rr3---sn-primary.googlevideo.com/videoplayback?mn=sn-primary,sn-backup&itag=140")!
        let failovers = LocalAudioProxy.buildFailoverURLs(for: ytURL)
        XCTAssertEqual(failovers.count, 2)
        XCTAssertEqual(failovers[0].host, "rr1---sn-backup.googlevideo.com")
        XCTAssertEqual(failovers[1].host, "rr2---sn-backup.googlevideo.com")

        // 2. End-to-end loopback proxy test with 403 -> onRefresh URL hot-swap
        let payload = Data((0..<(300 * 1024)).map { UInt8($0 & 0xFF) })
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ProxyTestURLProtocol.self]
        let mockSession = URLSession(configuration: cfg)

        let expiredHost = "expired.example.com"
        let freshHost = "fresh.example.com"
        ProxyTestURLProtocol.setHandler { req in
            if req.url?.host == expiredHost {
                let r = HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (r, Data())
            }
            let rangeHeader = req.value(forHTTPHeaderField: "Range") ?? "bytes=0-\(payload.count - 1)"
            let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
            let parts = cleaned.split(separator: "-")
            let start = Int(parts.first ?? "0") ?? 0
            let end = min(payload.count - 1, Int(parts.count > 1 ? parts[1] : "\(payload.count - 1)") ?? (payload.count - 1))
            let slice = payload[start...end]
            let headers = [
                "Content-Range": "bytes \(start)-\(end)/\(payload.count)",
                "Content-Length": "\(slice.count)",
                "Content-Type": "audio/mpeg",
            ]
            let resp = HTTPURLResponse(url: req.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (resp, Data(slice))
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("natch_proxy_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cache = ChunkRangeCache(directory: tmp.appendingPathComponent("cache"))
        let proxy = LocalAudioProxy(cache: cache, session: mockSession, tempDirectory: tmp.appendingPathComponent("buf"))
        defer { Task { await proxy.stop() } }

        let initial = ProxyStreamDescriptor(
            trackId: "proxy_t1",
            url: URL(string: "https://\(expiredHost)/song.mp3")!,
            mimeType: "audio/mpeg",
            contentLength: Int64(payload.count)
        )
        let localURL = try await proxy.registerStream(initial) { trackId in
            ProxyStreamDescriptor(
                trackId: trackId,
                url: URL(string: "https://\(freshHost)/song.mp3")!,
                mimeType: "audio/mpeg",
                contentLength: Int64(payload.count)
            )
        }
        XCTAssertEqual(localURL.host, "127.0.0.1")
        XCTAssertEqual(localURL.pathExtension, "mp3")

        let clientCfg = URLSessionConfiguration.ephemeral
        clientCfg.timeoutIntervalForRequest = 10
        clientCfg.timeoutIntervalForResource = 15
        let clientSession = URLSession(configuration: clientCfg)

        // HEAD check
        var headReq = URLRequest(url: localURL)
        headReq.httpMethod = "HEAD"
        let (_, headResp) = try await clientSession.data(for: headReq)
        let headHTTP = try XCTUnwrap(headResp as? HTTPURLResponse)
        XCTAssertEqual(headHTTP.statusCode, 200)
        XCTAssertEqual(headHTTP.value(forHTTPHeaderField: "Content-Length"), "\(payload.count)")

        // Range 206 check crossing 256 KB chunk boundary (forces chunk 0 + chunk 1 after 403 hot-swap)
        var getReq = URLRequest(url: localURL)
        getReq.setValue("bytes=260000-270000", forHTTPHeaderField: "Range")
        let (rangeData, rangeResp) = try await clientSession.data(for: getReq)
        let rangeHTTP = try XCTUnwrap(rangeResp as? HTTPURLResponse)
        XCTAssertEqual(rangeHTTP.statusCode, 206)
        XCTAssertEqual(rangeData, Data(payload[260_000...270_000]))
    }
}

private final class ProxyTestURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        _handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self._handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
