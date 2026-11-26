import XCTest
@testable import MochyAudio

final class MochyAudioTests: XCTestCase {
    func testWebMOpusDemuxerExtractsOpusPackets() {
        // Minimal synthetic Matroska/WebM binary with Tracks(CodecID="A_OPUS") + Cluster(Timecode=1000, SimpleBlock)
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
        // Track VINT=0x81, relTime=+20ms (0x00,0x14), flags=0x80 (keyframe)
        let simpleBlock = elem([0xA3], [0x81, 0x00, 0x14, 0x80] + opusPayload)
        let cluster = elem([0x1F, 0x43, 0xB6, 0x75], timecode + simpleBlock)
        let segment = elem([0x18, 0x53, 0x80, 0x67], tracks + cluster)

        let parsed = WebMOpusDemuxer.parse(data: Data(segment))
        XCTAssertEqual(parsed?.packets.count, 1)
        XCTAssertEqual(parsed?.packets.first?.timestampMs, 1020)
        XCTAssertEqual(parsed?.packets.first?.data, Data(opusPayload))
    }

    func testChunkRangeCacheStoresReadsAndEvictsLRU() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mochy_cache_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = ChunkRangeCache(directory: tmp, maxCacheBytes: 100)
        try await cache.storeChunk(mediaId: "m1", chunkIndex: 0, data: Data(repeating: 0x11, count: 70))
        let read1 = await cache.readChunk(mediaId: "m1", chunkIndex: 0)
        XCTAssertEqual(read1?.count, 70)

        try await cache.storeChunk(mediaId: "m2", chunkIndex: 0, data: Data(repeating: 0x22, count: 70))
        // m1 should be evicted when m2 pushed total over 100 bytes
        let evicted = await cache.readChunk(mediaId: "m1", chunkIndex: 0)
        let kept = await cache.readChunk(mediaId: "m2", chunkIndex: 0)
        XCTAssertNil(evicted)
        XCTAssertEqual(kept?.count, 70)
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
}
