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
}
