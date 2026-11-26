import XCTest
@testable import MochyCore
@testable import MochyInnerTube
@testable import MochyModules

final class MochyModulesTests: XCTestCase {
    func testFlacStreamInfoParserParses16BitAnd24BitHeaders() {
        // 16-bit / 44100 Hz / 2ch FLAC header
        // sampleRate = 44100 = 0x0AC44 -> b18=0x0A, b19=0xC4, b20=(4<<4)|(1<<1)|0 = 0x42, b21=(15<<4) = 0xF0
        var hdr16 = [UInt8](repeating: 0, count: 26)
        hdr16[0] = 0x66; hdr16[1] = 0x4C; hdr16[2] = 0x61; hdr16[3] = 0x43
        hdr16[18] = 0x0A; hdr16[19] = 0xC4; hdr16[20] = 0x42; hdr16[21] = 0xF0
        let info16 = FlacStreamInfoParser.parse(Data(hdr16))
        XCTAssertEqual(info16?.sampleRate, 44_100)
        XCTAssertEqual(info16?.channels, 2)
        XCTAssertEqual(info16?.bitsPerSample, 16)
        XCTAssertEqual(info16?.isHiRes, false)

        // 24-bit / 96000 Hz / 2ch FLAC header
        // 96000 = 0x17700 -> b18=0x17, b19=0x70, b20=(0<<4)|(1<<1)|1 = 0x03, b21=(7<<4) = 0x70
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
    }
}
