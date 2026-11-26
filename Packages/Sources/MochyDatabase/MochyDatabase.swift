import Foundation
import GRDB

public struct SchemaHealth: Sendable, Equatable {
    public let tableCount: Int
    public let viewCount: Int
    public let userVersion: Int
}

/// Thread-safe WAL SQLite store matching Mochy Music schema v47.
public final class MochyDatabase: @unchecked Sendable {
    public let dbWriter: any DatabaseWriter

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    /// Opens an on-disk WAL database at `path` (matching Mochy's PRAGMA tuning).
    public static func open(path: String) throws -> MochyDatabase {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try Self.applyPragmas(db, enableWalCheckpoint: true)
        }
        let pool = try DatabasePool(path: path, configuration: config)
        return try MochyDatabase(dbWriter: pool)
    }

    /// Opens an isolated in-memory database for unit tests.
    public static func inMemory() throws -> MochyDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try Self.applyPragmas(db, enableWalCheckpoint: false)
        }
        let queue = try DatabaseQueue(configuration: config)
        return try MochyDatabase(dbWriter: queue)
    }

    private static func applyPragmas(_ db: Database, enableWalCheckpoint: Bool) throws {
        try db.execute(sql: "PRAGMA foreign_keys = ON")
        try db.execute(sql: "PRAGMA busy_timeout = 60000")
        try db.execute(sql: "PRAGMA cache_size = -16000")
        if enableWalCheckpoint {
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 1000")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v47_initial") { db in
            for sql in MochyDatabaseSchema.v47DDLStatements {
                try db.execute(sql: sql)
            }
            try db.execute(sql: "PRAGMA user_version = \(MochyDatabaseSchema.version)")
        }
        return migrator
    }

    // MARK: - Diagnostics

    public func schemaHealthCheck() throws -> SchemaHealth {
        try dbWriter.read { db in
            let tables = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'"
            ) ?? 0
            let views = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'view'"
            ) ?? 0
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            return SchemaHealth(tableCount: tables, viewCount: views, userVersion: version)
        }
    }

    // MARK: - Songs & Artists

    public func upsertSong(_ song: SongEntity, artists: [ArtistEntity] = []) throws {
        try dbWriter.write { db in
            try song.save(db)
            if !artists.isEmpty {
                try db.execute(sql: "DELETE FROM song_artist_map WHERE songId = ?", arguments: [song.id])
                for (index, artist) in artists.enumerated() {
                    try artist.save(db)
                    try SongArtistMap(songId: song.id, artistId: artist.id, position: index).save(db)
                }
            }
        }
    }

    public func fetchSong(id: String) throws -> SongEntity? {
        try dbWriter.read { db in
            try SongEntity.fetchOne(db, key: id)
        }
    }

    public func fetchAllSongs() throws -> [SongEntity] {
        try dbWriter.read { db in
            try SongEntity.order(Column("title")).fetchAll(db)
        }
    }

    @discardableResult
    public func deleteSong(id: String) throws -> Bool {
        try dbWriter.write { db in
            try SongEntity.deleteOne(db, key: id)
        }
    }

    // MARK: - Playlists

    public func upsertPlaylist(_ playlist: PlaylistEntity) throws {
        try dbWriter.write { db in
            try playlist.save(db)
        }
    }

    public func addSongToPlaylist(
        playlistId: String,
        songId: String,
        position: Int? = nil,
        setVideoId: String? = nil
    ) throws {
        try dbWriter.write { db in
            let resolvedPos: Int
            if let position {
                resolvedPos = position
            } else {
                let maxPos = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(MAX(position), -1) FROM playlist_song_map WHERE playlistId = ?",
                    arguments: [playlistId]
                ) ?? -1
                resolvedPos = maxPos + 1
            }
            var entry = PlaylistSongMap(
                playlistId: playlistId,
                songId: songId,
                position: resolvedPos,
                setVideoId: setVideoId
            )
            try entry.insert(db)
        }
    }

    public func fetchPlaylistSongs(playlistId: String) throws -> [SongEntity] {
        try dbWriter.read { db in
            let sql = """
            SELECT song.* FROM song
            INNER JOIN playlist_song_map ON playlist_song_map.songId = song.id
            WHERE playlist_song_map.playlistId = ?
            ORDER BY playlist_song_map.position ASC
            """
            return try SongEntity.fetchAll(db, sql: sql, arguments: [playlistId])
        }
    }

    // MARK: - Non-destructive SongEdits

    public func upsertSongEdit(_ edit: SongEdit) throws {
        try dbWriter.write { db in
            try edit.save(db)
        }
    }

    public func fetchSongEdit(songId: String) throws -> SongEdit? {
        try dbWriter.read { db in
            try SongEdit.fetchOne(db, key: songId)
        }
    }

    // MARK: - Formats & Lyrics

    public func upsertFormat(_ format: FormatEntity) throws {
        try dbWriter.write { db in
            try format.save(db)
        }
    }

    public func fetchFormat(id: String) throws -> FormatEntity? {
        try dbWriter.read { db in
            try FormatEntity.fetchOne(db, key: id)
        }
    }

    public func upsertLyrics(_ lyrics: LyricsEntity) throws {
        try dbWriter.write { db in
            try lyrics.save(db)
        }
    }

    public func fetchLyrics(id: String) throws -> LyricsEntity? {
        try dbWriter.read { db in
            try LyricsEntity.fetchOne(db, key: id)
        }
    }

    // MARK: - Crossmix / MixIt Transitions

    public func upsertTransition(_ transition: PlaylistTransition) throws {
        try dbWriter.write { db in
            try transition.save(db)
        }
    }

    public func fetchTransitions(playlistId: String) throws -> [PlaylistTransition] {
        try dbWriter.read { db in
            try PlaylistTransition
                .filter(Column("playlistId") == playlistId)
                .fetchAll(db)
        }
    }

    // MARK: - Speed Dial (with Mochy's FIFO MaxPinned eviction)

    public func pinToSpeedDial(_ item: SpeedDialItem, maxPinned: Int = 24) throws {
        try dbWriter.write { db in
            try item.save(db)
            let count = try SpeedDialItem.fetchCount(db)
            if count > maxPinned {
                let overflow = count - maxPinned
                try db.execute(
                    sql: """
                    DELETE FROM speed_dial_item WHERE id IN (
                        SELECT id FROM speed_dial_item ORDER BY createDate ASC LIMIT ?
                    )
                    """,
                    arguments: [overflow]
                )
            }
        }
    }

    public func fetchSpeedDialItems() throws -> [SpeedDialItem] {
        try dbWriter.read { db in
            try SpeedDialItem.order(Column("createDate").desc).fetchAll(db)
        }
    }

    // MARK: - Search History

    public func recordSearch(query: String) throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM search_history WHERE query = ?", arguments: [trimmed])
            var entry = SearchHistoryEntry(query: trimmed)
            try entry.insert(db)
        }
    }

    public func recentSearches(limit: Int = 30) throws -> [String] {
        try dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT query FROM search_history ORDER BY id DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }
}
