import XCTest
@testable import MochyCore
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

    func testTransferArchivePreservesSongsEditsArtistsAndPlaylistMaps() throws {
        let srcDb = try MochyDatabase.inMemory()
        try srcDb.upsertSong(
            SongEntity(id: "s1", title: "Exported Song", duration: 185),
            artists: [ArtistEntity(id: "a1", name: "Natch Artist")]
        )
        try srcDb.upsertSong(SongEntity(id: "s2", title: "Second Song", duration: 210))
        try srcDb.upsertSongEdit(SongEdit(songId: "s1", title: "Custom"))
        try srcDb.upsertPlaylist(PlaylistEntity(id: "pl1", name: "Roadtrip Mix", isLocal: true))
        try srcDb.addSongToPlaylist(playlistId: "pl1", songId: "s1", position: 0)
        try srcDb.addSongToPlaylist(playlistId: "pl1", songId: "s2", position: 1)

        let json = try TransferArchive.exportJSON(from: srcDb)

        let dstDb = try MochyDatabase.inMemory()
        let importedCount = try TransferArchive.importJSON(json, into: dstDb)
        XCTAssertEqual(importedCount, 2)
        XCTAssertEqual(try dstDb.fetchSongEdit(songId: "s1")?.title, "Custom")
        let restoredPlSongs = try dstDb.fetchPlaylistSongs(playlistId: "pl1")
        XCTAssertEqual(restoredPlSongs.map(\.id), ["s1", "s2"])
        let restoredArtists = try dstDb.fetchArtistsForSong(songId: "s1")
        XCTAssertEqual(restoredArtists.map(\.name), ["Natch Artist"])

        let sig = LastFmScrobbler.signParameters(["method": "track.scrobble", "artist": "Mochy"], sharedSecret: "sec")
        XCTAssertEqual(sig.count, 32)
    }

    func testPlaylistImportServiceParsesSpotifyEmbedAndAppleMusicHTML() {
        let spotifyHTML = """
        <html><body>
        <script id="__NEXT_DATA__" type="application/json">
        {"props":{"pageProps":{"state":{"data":{"entity":{"name":"Midnight Drive","trackList":[{"title":"Nightcall","subtitle":"Kavinsky","duration":258000},{"title":"After Dark","subtitle":"Mr.Kitty","duration":259000}]}}}}}}
        </script>
        </body></html>
        """
        let sp = PlaylistImportService.parseSpotifyEmbedHTML(spotifyHTML)
        XCTAssertEqual(sp?.name, "Midnight Drive")
        XCTAssertEqual(sp?.tracks.count, 2)
        XCTAssertEqual(sp?.tracks[0].title, "Nightcall")
        XCTAssertEqual(sp?.tracks[0].artist, "Kavinsky")
        XCTAssertEqual(sp?.tracks[0].durationSeconds, 258)

        let appleHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@type":"MusicPlaylist","name":"Chill Tokyo","track":[{"name":"Plastic Love","byArtist":{"name":"Mariya Takeuchi"}},{"name":"Stay With Me","byArtist":[{"name":"Miki Matsubara"}]}]}
        </script>
        </head><body></body></html>
        """
        let am = PlaylistImportService.parseAppleMusicHTML(appleHTML)
        XCTAssertEqual(am?.name, "Chill Tokyo")
        XCTAssertEqual(am?.tracks.count, 2)
        XCTAssertEqual(am?.tracks[0].title, "Plastic Love")
        XCTAssertEqual(am?.tracks[0].artist, "Mariya Takeuchi")
        XCTAssertEqual(am?.tracks[1].artist, "Miki Matsubara")
    }

    func testCode128RecapBarcodeMatchesExpectedFormat() {
        let bits = Code128Encoder.encode("MFY2026-11")
        XCTAssertFalse(bits.isEmpty)
        XCTAssertGreaterThan(bits.count, 100)
    }
}
