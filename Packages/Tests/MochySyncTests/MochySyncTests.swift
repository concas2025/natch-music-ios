import XCTest
@testable import MochyDatabase
@testable import MochySync

final class MochySyncTests: XCTestCase {
    func testLinkImporterAndCsvRoundTrip() {
        let sp = LinkImporter.parse(urlString: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc")
        XCTAssertEqual(sp?.service, .spotify)
        XCTAssertEqual(sp?.kind, "playlist")
        XCTAssertEqual(sp?.remoteId, "37i9dQZF1DXcBWIGoYBM5M")

        let yt = LinkImporter.parse(urlString: "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(yt?.service, .youtube)
        XCTAssertEqual(yt?.remoteId, "dQw4w9WgXcQ")

        let csv = CsvImporter.exportCSV(songs: [
            (SongEntity(id: "s1", title: "Hello, World", duration: 200, albumName: "Album \"A\""), "Artist 1, Artist 2"),
        ])
        let parsed = CsvImporter.parseTracks(csv: csv)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Hello, World")
        XCTAssertEqual(parsed[0].album, "Album \"A\"")
        XCTAssertEqual(parsed[0].durationSeconds, 200)
    }

    func testTransferArchiveAndLastFmSignature() throws {
        let srcDb = try MochyDatabase.inMemory()
        try srcDb.upsertSong(SongEntity(id: "s1", title: "Exported Song", duration: 185))
        try srcDb.upsertSongEdit(SongEdit(songId: "s1", title: "Custom"))
        let json = try TransferArchive.exportJSON(from: srcDb)

        let dstDb = try MochyDatabase.inMemory()
        let importedCount = try TransferArchive.importJSON(json, into: dstDb)
        XCTAssertEqual(importedCount, 1)
        XCTAssertEqual(try dstDb.fetchSongEdit(songId: "s1")?.title, "Custom")

        let sig = LastFmScrobbler.signParameters(["method": "track.scrobble", "artist": "Mochy"], sharedSecret: "sec")
        XCTAssertEqual(sig.count, 32)
    }
}
