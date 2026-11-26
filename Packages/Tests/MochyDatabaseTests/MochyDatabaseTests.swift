import GRDB
import XCTest
@testable import MochyDatabase

final class MochyDatabaseTests: XCTestCase {
    func testSchemaV47CreatesAll25TablesAnd3Views() throws {
        let db = try MochyDatabase.inMemory()
        let health = try db.schemaHealthCheck()
        XCTAssertEqual(health.tableCount, 25)
        XCTAssertEqual(health.viewCount, 3)
        XCTAssertEqual(health.userVersion, 47)
    }

    func testCascadeDeleteNonDestructiveEditAndPlaylistTransition() throws {
        let db = try MochyDatabase.inMemory()

        let song1 = SongEntity(id: "s1", title: "Track One", duration: 210)
        let song2 = SongEntity(id: "s2", title: "Track Two", duration: 195)
        let artist = ArtistEntity(id: "a1", name: "Artist A")
        try db.upsertSong(song1, artists: [artist])
        try db.upsertSong(song2, artists: [artist])

        let playlist = PlaylistEntity(id: "p1", name: "Mix Playlist", mixItEnabled: true)
        try db.upsertPlaylist(playlist)
        try db.addSongToPlaylist(playlistId: "p1", songId: "s1", position: 0)
        try db.addSongToPlaylist(playlistId: "p1", songId: "s2", position: 1)

        // Non-destructive edit leaves base song unchanged
        try db.upsertSongEdit(SongEdit(songId: "s1", title: "Custom Edited Title", noVideo: true))
        XCTAssertEqual(try db.fetchSong(id: "s1")?.title, "Track One")
        XCTAssertEqual(try db.fetchSongEdit(songId: "s1")?.title, "Custom Edited Title")

        // v47 PlaylistTransition stem levels
        let transition = PlaylistTransition(
            playlistId: "p1",
            fromSongId: "s1",
            toSongId: "s2",
            outStartMs: 180_000,
            inStartMs: 4_000,
            durationMs: 8_000,
            outVoiceLevel: 0.4,
            outBassLevel: 0.0,
            inInstrumentLevel: 0.9
        )
        try db.upsertTransition(transition)
        let transitions = try db.fetchTransitions(playlistId: "p1")
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].outVoiceLevel, 0.4, accuracy: 0.0001)
        XCTAssertEqual(transitions[0].outBassLevel, 0.0, accuracy: 0.0001)
        XCTAssertEqual(transitions[0].inInstrumentLevel, 0.9, accuracy: 0.0001)

        // Preview view caps at position <= 3
        let s3 = SongEntity(id: "s3", title: "Track 3")
        let s4 = SongEntity(id: "s4", title: "Track 4")
        let s5 = SongEntity(id: "s5", title: "Track 5")
        try db.upsertSong(s3)
        try db.upsertSong(s4)
        try db.upsertSong(s5)
        try db.addSongToPlaylist(playlistId: "p1", songId: "s3", position: 2)
        try db.addSongToPlaylist(playlistId: "p1", songId: "s4", position: 3)
        try db.addSongToPlaylist(playlistId: "p1", songId: "s5", position: 4)

        let previewCount = try db.dbWriter.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM playlist_song_map_preview WHERE playlistId = 'p1'")
        }
        XCTAssertEqual(previewCount, 4) // positions 0, 1, 2, 3

        // Deleting song cascades to playlist_song_map & song_artist_map
        try db.deleteSong(id: "s1")
        let remainingSongs = try db.fetchPlaylistSongs(playlistId: "p1")
        XCTAssertEqual(remainingSongs.map(\.id), ["s2", "s3", "s4", "s5"])
    }

    func testPinToSpeedDialEvictsOldestAtCapacity() throws {
        let db = try MochyDatabase.inMemory()
        for i in 1...25 {
            try db.pinToSpeedDial(
                SpeedDialItem(id: "sd-\(i)", title: "Item \(i)", type: "song", createDate: Int64(i * 100)),
                maxPinned: 24
            )
        }
        let items = try db.fetchSpeedDialItems()
        XCTAssertEqual(items.count, 24)
        XCTAssertFalse(items.contains { $0.id == "sd-1" })
        XCTAssertEqual(items.first?.id, "sd-25")
    }

    func testLyricsOffsetRecapTelemetryAndSyncUndoSnapshot() throws {
        let db = try MochyDatabase.inMemory()
        try db.upsertSong(
            SongEntity(id: "s1", title: "Track One", duration: 200, liked: true),
            artists: [ArtistEntity(id: "a1", name: "Artist Alpha")]
        )
        try db.updateLyricsOffset(songId: "s1", offsetMs: -350)
        XCTAssertEqual(try db.fetchSong(id: "s1")?.lyricsOffset, -350)

        try db.recordPlayEvent(songId: "s1", playTimeMs: 120_000)
        let weekdays = try db.fetchWeekdayPlayTimeMs()
        XCTAssertEqual(weekdays.count, 7)
        XCTAssertEqual(weekdays.reduce(0, +), 120_000)

        let topArtists = try db.fetchTopArtists(limit: 5)
        XCTAssertEqual(topArtists.first?.artist.name, "Artist Alpha")
        XCTAssertEqual(topArtists.first?.playTimeMs, 120_000)

        try db.upsertPlaylist(PlaylistEntity(id: "pl_keep", name: "Keep"))
        try db.upsertPlaylist(PlaylistEntity(id: "pl_drop", name: "Drop"))
        try db.restoreSyncSnapshot(keepPlaylistIds: ["pl_keep"], likedSongIds: [])
        XCTAssertEqual(try db.fetchPlaylists().map(\.id), ["pl_keep"])
        XCTAssertEqual(try db.fetchSong(id: "s1")?.liked, false)
    }
}
