import Foundation
import GRDB

public struct RecognitionHistoryEntity: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "recognition_history"

    public var id: Int64?
    public var trackId: String
    public var title: String
    public var artist: String
    public var album: String?
    public var coverArtUrl: String?
    public var coverArtHqUrl: String?
    public var genre: String?
    public var releaseDate: String?
    public var label: String?
    public var shazamUrl: String?
    public var appleMusicUrl: String?
    public var spotifyUrl: String?
    public var isrc: String?
    public var youtubeVideoId: String?
    public var recognizedAt: Int64
    public var liked: Bool

    public init(
        id: Int64? = nil,
        trackId: String,
        title: String,
        artist: String,
        album: String? = nil,
        coverArtUrl: String? = nil,
        coverArtHqUrl: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        label: String? = nil,
        shazamUrl: String? = nil,
        appleMusicUrl: String? = nil,
        spotifyUrl: String? = nil,
        isrc: String? = nil,
        youtubeVideoId: String? = nil,
        recognizedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        liked: Bool = false
    ) {
        self.id = id
        self.trackId = trackId
        self.title = title
        self.artist = artist
        self.album = album
        self.coverArtUrl = coverArtUrl
        self.coverArtHqUrl = coverArtHqUrl
        self.genre = genre
        self.releaseDate = releaseDate
        self.label = label
        self.shazamUrl = shazamUrl
        self.appleMusicUrl = appleMusicUrl
        self.spotifyUrl = spotifyUrl
        self.isrc = isrc
        self.youtubeVideoId = youtubeVideoId
        self.recognizedAt = recognizedAt
        self.liked = liked
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ImportedPlaylistEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "imported_playlist"

    public var playlistId: String
    public var source: String
    public var sessionId: Int64
    public var importedAt: Int64
    public var remoteId: String?
    public var remoteUrl: String?
    public var lastSyncedAt: Int64?
    public var authorName: String?
    public var authorAvatarUrl: String?
    public var authorUrl: String?

    public init(
        playlistId: String,
        source: String,
        sessionId: Int64,
        importedAt: Int64,
        remoteId: String? = nil,
        remoteUrl: String? = nil,
        lastSyncedAt: Int64? = nil,
        authorName: String? = nil,
        authorAvatarUrl: String? = nil,
        authorUrl: String? = nil
    ) {
        self.playlistId = playlistId
        self.source = source
        self.sessionId = sessionId
        self.importedAt = importedAt
        self.remoteId = remoteId
        self.remoteUrl = remoteUrl
        self.lastSyncedAt = lastSyncedAt
        self.authorName = authorName
        self.authorAvatarUrl = authorAvatarUrl
        self.authorUrl = authorUrl
    }
}

public struct ImportSessionEntity: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "import_session"

    public var id: Int64?
    public var source: String
    public var startedAt: Int64

    public init(id: Int64? = nil, source: String, startedAt: Int64) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ImportedSongEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "imported_song"
    public var songId: String
    public var source: String
    public var importedAt: Int64

    public init(songId: String, source: String, importedAt: Int64) {
        self.songId = songId
        self.source = source
        self.importedAt = importedAt
    }
}

extension MochyDatabase {
    public func fetchPlaylists() throws -> [PlaylistEntity] {
        try dbWriter.read { db in
            try PlaylistEntity.order(Column("lastUpdateTime").desc).fetchAll(db)
        }
    }

    public func fetchAlbums() throws -> [AlbumEntity] {
        try dbWriter.read { db in
            try AlbumEntity.order(Column("title").asc).fetchAll(db)
        }
    }

    public func fetchArtists() throws -> [ArtistEntity] {
        try dbWriter.read { db in
            try ArtistEntity.order(Column("name").asc).fetchAll(db)
        }
    }

    public func fetchLikedSongs() throws -> [SongEntity] {
        try dbWriter.read { db in
            try SongEntity.filter(Column("liked") == true).order(Column("likedDate").desc).fetchAll(db)
        }
    }

    public func fetchArtistsForSong(songId: String) throws -> [ArtistEntity] {
        try dbWriter.read { db in
            let sql = """
            SELECT artist.* FROM artist
            INNER JOIN sorted_song_artist_map ON sorted_song_artist_map.artistId = artist.id
            WHERE sorted_song_artist_map.songId = ?
            """
            return try ArtistEntity.fetchAll(db, sql: sql, arguments: [songId])
        }
    }

    public func toggleLike(songId: String) throws -> Bool {
        try dbWriter.write { db in
            guard var song = try SongEntity.fetchOne(db, key: songId) else { return false }
            song.liked.toggle()
            song.likedDate = song.liked ? Int64(Date().timeIntervalSince1970 * 1000) : nil
            try song.save(db)
            return song.liked
        }
    }

    public func upsertAlbum(_ album: AlbumEntity) throws {
        try dbWriter.write { db in
            try album.save(db)
        }
    }

    public func fetchAllSongEdits() throws -> [SongEdit] {
        try dbWriter.read { db in
            try SongEdit.fetchAll(db)
        }
    }

    public func fetchAllTransitions() throws -> [PlaylistTransition] {
        try dbWriter.read { db in
            try PlaylistTransition.fetchAll(db)
        }
    }

    public func recordPlayEvent(songId: String, playTimeMs: Int64) throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        try dbWriter.write { db in
            var event = EventEntity(songId: songId, timestamp: nowMs, playTime: playTimeMs)
            try event.insert(db)

            try db.execute(
                sql: "UPDATE song SET totalPlayTime = totalPlayTime + ? WHERE id = ?",
                arguments: [playTimeMs, songId]
            )
            try db.execute(
                sql: """
                INSERT INTO playCount (song, year, month, count) VALUES (?, ?, ?, 1)
                ON CONFLICT(song, year, month) DO UPDATE SET count = count + 1
                """,
                arguments: [songId, year, month]
            )
        }
    }

    public func fetchTopSongs(limit: Int = 20) throws -> [SongEntity] {
        try dbWriter.read { db in
            try SongEntity.order(Column("totalPlayTime").desc).limit(limit).fetchAll(db)
        }
    }

    public func fetchTotalPlayTimeMs() throws -> Int64 {
        try dbWriter.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(totalPlayTime), 0) FROM song") ?? 0
        }
    }

    public func fetchRecentEvents(limit: Int = 50) throws -> [EventEntity] {
        try dbWriter.read { db in
            try EventEntity.order(Column("timestamp").desc).limit(limit).fetchAll(db)
        }
    }

    public func saveRecognition(_ entry: RecognitionHistoryEntity) throws {
        try dbWriter.write { db in
            var copy = entry
            try copy.insert(db)
        }
    }

    public func fetchRecognitionHistory(limit: Int = 30) throws -> [RecognitionHistoryEntity] {
        try dbWriter.read { db in
            try RecognitionHistoryEntity.order(Column("recognizedAt").desc).limit(limit).fetchAll(db)
        }
    }

    public func recordImportedPlaylist(
        playlist: PlaylistEntity,
        songs: [(song: SongEntity, artists: [ArtistEntity])],
        source: String,
        remoteId: String?,
        remoteUrl: String?
    ) throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try dbWriter.write { db in
            try playlist.save(db)
            var session = ImportSessionEntity(source: source, startedAt: nowMs)
            try session.insert(db)
            let sessionId = session.id ?? 0

            for (idx, item) in songs.enumerated() {
                try item.song.save(db)
                for (aIdx, artist) in item.artists.enumerated() {
                    try artist.save(db)
                    try SongArtistMap(songId: item.song.id, artistId: artist.id, position: aIdx).save(db)
                }
                var map = PlaylistSongMap(playlistId: playlist.id, songId: item.song.id, position: idx)
                try map.insert(db)
                try ImportedSongEntity(songId: item.song.id, source: source, importedAt: nowMs).save(db)
            }

            try ImportedPlaylistEntity(
                playlistId: playlist.id,
                source: source,
                sessionId: sessionId,
                importedAt: nowMs,
                remoteId: remoteId,
                remoteUrl: remoteUrl,
                lastSyncedAt: nowMs
            ).save(db)
        }
    }

    public func fetchImportedPlaylistIds() throws -> Set<String> {
        try dbWriter.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT playlistId FROM imported_playlist")
            return Set(ids)
        }
    }

    public func updateLyricsOffset(songId: String, offsetMs: Int) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE song SET lyricsOffset = ? WHERE id = ?",
                arguments: [offsetMs, songId]
            )
        }
    }

    public func deletePlaylist(id: String) throws {
        try dbWriter.write { db in
            try PlaylistEntity.deleteOne(db, key: id)
        }
    }

    public func replacePlaylistSongs(playlistId: String, songIds: [String]) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlistId = ?", arguments: [playlistId])
            for (idx, songId) in songIds.enumerated() {
                var entry = PlaylistSongMap(playlistId: playlistId, songId: songId, position: idx)
                try entry.insert(db)
            }
        }
    }

    public func fetchAllSongArtistMaps() throws -> [SongArtistMap] {
        try dbWriter.read { db in
            try SongArtistMap.fetchAll(db)
        }
    }

    public func fetchAllPlaylistSongMaps() throws -> [PlaylistSongMap] {
        try dbWriter.read { db in
            try PlaylistSongMap.order(Column("playlistId"), Column("position")).fetchAll(db)
        }
    }

    public func upsertArtist(_ artist: ArtistEntity) throws {
        try dbWriter.write { db in
            try artist.save(db)
        }
    }

    public func upsertSongArtistMap(_ map: SongArtistMap) throws {
        try dbWriter.write { db in
            try map.save(db)
        }
    }

    /// Returns total listening milliseconds grouped by weekday (Monday = 0 .. Sunday = 6) for Recap Story charts.
    public func fetchWeekdayPlayTimeMs() throws -> [Int64] {
        let events = try dbWriter.read { db in
            try EventEntity.fetchAll(db)
        }
        var totals = [Int64](repeating: 0, count: 7)
        let cal = Calendar.current
        for ev in events {
            let date = Date(timeIntervalSince1970: TimeInterval(ev.timestamp) / 1000.0)
            let weekday = cal.component(.weekday, from: date) // 1 = Sun, 2 = Mon .. 7 = Sat
            let monBased = (weekday + 5) % 7
            totals[monBased] += max(0, ev.playTime)
        }
        return totals
    }

    /// Returns top artists ranked by cumulative play time of their songs.
    public func fetchTopArtists(limit: Int = 10) throws -> [(artist: ArtistEntity, playTimeMs: Int64)] {
        try dbWriter.read { db in
            let sql = """
            SELECT artist.*, COALESCE(SUM(song.totalPlayTime), 0) AS totalMs
            FROM artist
            INNER JOIN song_artist_map ON song_artist_map.artistId = artist.id
            INNER JOIN song ON song.id = song_artist_map.songId
            GROUP BY artist.id
            ORDER BY totalMs DESC
            LIMIT ?
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
            return rows.compactMap { row -> (ArtistEntity, Int64)? in
                guard let artist = try? ArtistEntity(row: row) else { return nil }
                let ms: Int64 = row["totalMs"] ?? 0
                return (artist, ms)
            }
        }
    }

    /// Restores liked states & removes playlists not in `keepPlaylistIds` (for `YouTubeSyncManager.undoLastSync`).
    public func restoreSyncSnapshot(keepPlaylistIds: Set<String>, likedSongIds: Set<String>) throws {
        try dbWriter.write { db in
            let allPlaylists = try PlaylistEntity.fetchAll(db)
            for pl in allPlaylists where !keepPlaylistIds.contains(pl.id) {
                try PlaylistEntity.deleteOne(db, key: pl.id)
            }
            let allSongs = try SongEntity.fetchAll(db)
            for var song in allSongs {
                let shouldBeLiked = likedSongIds.contains(song.id)
                if song.liked != shouldBeLiked {
                    song.liked = shouldBeLiked
                    song.likedDate = shouldBeLiked ? (song.likedDate ?? Int64(Date().timeIntervalSince1970 * 1000)) : nil
                    try song.save(db)
                }
            }
        }
    }
}
