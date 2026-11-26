import Foundation

/// Exact SQLite schema matching Mochy Music Room Database v47 (25 tables + indices + 3 views).
public enum MochyDatabaseSchema {
    public static let version = 47

    public static let tableDDLStatements: [String] = [
        // 1. song
        """
        CREATE TABLE IF NOT EXISTS song (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            duration INTEGER NOT NULL,
            thumbnailUrl TEXT,
            albumId TEXT,
            albumName TEXT,
            explicit INTEGER NOT NULL DEFAULT 0,
            year INTEGER,
            date INTEGER,
            dateModified INTEGER,
            liked INTEGER NOT NULL DEFAULT 0,
            likedDate INTEGER,
            totalPlayTime INTEGER NOT NULL DEFAULT 0,
            inLibrary INTEGER,
            dateDownload INTEGER,
            isLocal INTEGER NOT NULL DEFAULT 0,
            libraryAddToken TEXT,
            libraryRemoveToken TEXT,
            lyricsOffset INTEGER NOT NULL DEFAULT 0,
            romanizeLyrics INTEGER NOT NULL DEFAULT 1,
            isDownloaded INTEGER NOT NULL DEFAULT 0,
            isUploaded INTEGER NOT NULL DEFAULT 0,
            isVideo INTEGER NOT NULL DEFAULT 0,
            localUri TEXT DEFAULT NULL,
            addedByLike INTEGER NOT NULL DEFAULT 0,
            genre TEXT
        )
        """,
        // 2. artist
        """
        CREATE TABLE IF NOT EXISTS artist (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            thumbnailUrl TEXT,
            channelId TEXT,
            lastUpdateTime INTEGER NOT NULL,
            bookmarkedAt INTEGER,
            isLocal INTEGER NOT NULL DEFAULT 0
        )
        """,
        // 3. album
        """
        CREATE TABLE IF NOT EXISTS album (
            id TEXT NOT NULL PRIMARY KEY,
            playlistId TEXT,
            title TEXT NOT NULL,
            year INTEGER,
            thumbnailUrl TEXT,
            themeColor INTEGER,
            songCount INTEGER NOT NULL,
            duration INTEGER NOT NULL,
            explicit INTEGER NOT NULL DEFAULT 0,
            lastUpdateTime INTEGER NOT NULL,
            bookmarkedAt INTEGER,
            likedDate INTEGER,
            inLibrary INTEGER,
            description TEXT,
            isLocal INTEGER NOT NULL DEFAULT 0,
            isUploaded INTEGER NOT NULL DEFAULT 0
        )
        """,
        // 4. playlist
        """
        CREATE TABLE IF NOT EXISTS playlist (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            browseId TEXT,
            createdAt INTEGER,
            lastUpdateTime INTEGER,
            isEditable INTEGER NOT NULL DEFAULT 1,
            bookmarkedAt INTEGER,
            remoteSongCount INTEGER,
            playEndpointParams TEXT,
            thumbnailUrl TEXT,
            shuffleEndpointParams TEXT,
            radioEndpointParams TEXT,
            isLocal INTEGER NOT NULL DEFAULT 0,
            isAutoSync INTEGER NOT NULL DEFAULT 0,
            description TEXT DEFAULT NULL,
            mixItEnabled INTEGER NOT NULL DEFAULT 0,
            mixItFallback TEXT
        )
        """,
        // 5. song_artist_map
        """
        CREATE TABLE IF NOT EXISTS song_artist_map (
            songId TEXT NOT NULL,
            artistId TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (songId, artistId),
            FOREIGN KEY (songId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE,
            FOREIGN KEY (artistId) REFERENCES artist(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 6. song_album_map
        """
        CREATE TABLE IF NOT EXISTS song_album_map (
            songId TEXT NOT NULL,
            albumId TEXT NOT NULL,
            "index" INTEGER NOT NULL,
            PRIMARY KEY (songId, albumId),
            FOREIGN KEY (songId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE,
            FOREIGN KEY (albumId) REFERENCES album(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 7. album_artist_map
        """
        CREATE TABLE IF NOT EXISTS album_artist_map (
            albumId TEXT NOT NULL,
            artistId TEXT NOT NULL,
            "order" INTEGER NOT NULL,
            PRIMARY KEY (albumId, artistId),
            FOREIGN KEY (albumId) REFERENCES album(id) ON UPDATE NO ACTION ON DELETE CASCADE,
            FOREIGN KEY (artistId) REFERENCES artist(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 8. playlist_song_map
        """
        CREATE TABLE IF NOT EXISTS playlist_song_map (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            playlistId TEXT NOT NULL,
            songId TEXT NOT NULL,
            position INTEGER NOT NULL,
            setVideoId TEXT,
            FOREIGN KEY (playlistId) REFERENCES playlist(id) ON UPDATE NO ACTION ON DELETE CASCADE,
            FOREIGN KEY (songId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 9. search_history
        """
        CREATE TABLE IF NOT EXISTS search_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            query TEXT NOT NULL
        )
        """,
        // 10. format
        """
        CREATE TABLE IF NOT EXISTS format (
            id TEXT NOT NULL PRIMARY KEY,
            itag INTEGER NOT NULL,
            mimeType TEXT NOT NULL,
            codecs TEXT NOT NULL,
            bitrate INTEGER NOT NULL,
            sampleRate INTEGER,
            contentLength INTEGER NOT NULL,
            loudnessDb REAL,
            perceptualLoudnessDb REAL,
            playbackUrl TEXT
        )
        """,
        // 11. lyrics
        """
        CREATE TABLE IF NOT EXISTS lyrics (
            id TEXT NOT NULL PRIMARY KEY,
            lyrics TEXT NOT NULL,
            provider TEXT NOT NULL DEFAULT 'Unknown',
            translatedLyrics TEXT NOT NULL DEFAULT '',
            translationLanguage TEXT NOT NULL DEFAULT '',
            translationMode TEXT NOT NULL DEFAULT ''
        )
        """,
        // 12. event
        """
        CREATE TABLE IF NOT EXISTS event (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            songId TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            playTime INTEGER NOT NULL,
            FOREIGN KEY (songId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 13. related_song_map
        """
        CREATE TABLE IF NOT EXISTS related_song_map (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            songId TEXT NOT NULL,
            relatedSongId TEXT NOT NULL,
            FOREIGN KEY (songId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE,
            FOREIGN KEY (relatedSongId) REFERENCES song(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 14. set_video_id
        """
        CREATE TABLE IF NOT EXISTS set_video_id (
            videoId TEXT NOT NULL PRIMARY KEY,
            setVideoId TEXT
        )
        """,
        // 15. playCount
        """
        CREATE TABLE IF NOT EXISTS playCount (
            song TEXT NOT NULL,
            year INTEGER NOT NULL,
            month INTEGER NOT NULL,
            count INTEGER NOT NULL,
            PRIMARY KEY (song, year, month)
        )
        """,
        // 16. recognition_history
        """
        CREATE TABLE IF NOT EXISTS recognition_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            trackId TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT,
            coverArtUrl TEXT,
            coverArtHqUrl TEXT,
            genre TEXT,
            releaseDate TEXT,
            label TEXT,
            shazamUrl TEXT,
            appleMusicUrl TEXT,
            spotifyUrl TEXT,
            isrc TEXT,
            youtubeVideoId TEXT,
            recognizedAt INTEGER NOT NULL,
            liked INTEGER NOT NULL DEFAULT 0
        )
        """,
        // 17. speed_dial_item
        """
        CREATE TABLE IF NOT EXISTS speed_dial_item (
            id TEXT NOT NULL PRIMARY KEY,
            secondaryId TEXT,
            title TEXT NOT NULL,
            subtitle TEXT,
            thumbnailUrl TEXT,
            type TEXT NOT NULL,
            explicit INTEGER NOT NULL DEFAULT 0,
            createDate INTEGER NOT NULL
        )
        """,
        // 18. playlist_event
        """
        CREATE TABLE IF NOT EXISTS playlist_event (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            playlistId TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (playlistId) REFERENCES playlist(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
        // 19. imported_song
        """
        CREATE TABLE IF NOT EXISTS imported_song (
            songId TEXT NOT NULL,
            source TEXT NOT NULL,
            importedAt INTEGER NOT NULL,
            PRIMARY KEY (songId, source)
        )
        """,
        // 20. import_session
        """
        CREATE TABLE IF NOT EXISTS import_session (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            source TEXT NOT NULL,
            startedAt INTEGER NOT NULL
        )
        """,
        // 21. import_session_song
        """
        CREATE TABLE IF NOT EXISTS import_session_song (
            sessionId INTEGER NOT NULL,
            songId TEXT NOT NULL,
            addedToLibrary INTEGER NOT NULL,
            liked INTEGER NOT NULL,
            PRIMARY KEY (sessionId, songId)
        )
        """,
        // 22. imported_playlist
        """
        CREATE TABLE IF NOT EXISTS imported_playlist (
            playlistId TEXT NOT NULL PRIMARY KEY,
            source TEXT NOT NULL,
            sessionId INTEGER NOT NULL,
            importedAt INTEGER NOT NULL,
            remoteId TEXT,
            remoteUrl TEXT,
            lastSyncedAt INTEGER,
            authorName TEXT,
            authorAvatarUrl TEXT,
            authorUrl TEXT
        )
        """,
        // 23. imported_playlist_track
        """
        CREATE TABLE IF NOT EXISTS imported_playlist_track (
            playlistId TEXT NOT NULL,
            trackKey TEXT NOT NULL,
            PRIMARY KEY (playlistId, trackKey)
        )
        """,
        // 24. song_edit
        """
        CREATE TABLE IF NOT EXISTS song_edit (
            songId TEXT NOT NULL PRIMARY KEY,
            title TEXT,
            artists TEXT,
            album TEXT,
            year INTEGER,
            cover TEXT,
            videoId TEXT,
            noVideo INTEGER NOT NULL DEFAULT 0
        )
        """,
        // 25. playlist_transition
        """
        CREATE TABLE IF NOT EXISTS playlist_transition (
            playlistId TEXT NOT NULL,
            fromSongId TEXT NOT NULL,
            toSongId TEXT NOT NULL,
            outStartMs INTEGER NOT NULL,
            inStartMs INTEGER NOT NULL,
            durationMs INTEGER NOT NULL,
            outEffect TEXT,
            inEffect TEXT,
            outFadeStart REAL,
            outFadeEnd REAL,
            inFadeStart REAL,
            inFadeEnd REAL,
            beatMatchMode TEXT,
            snapToBeat INTEGER,
            bassSwap INTEGER,
            swapFrac REAL,
            beatNudgeMs INTEGER,
            customSpeedRatio REAL,
            presetName TEXT,
            updatedAt INTEGER NOT NULL,
            outVoiceLevel REAL NOT NULL DEFAULT 1.0,
            outBassLevel REAL NOT NULL DEFAULT 1.0,
            outInstrumentLevel REAL NOT NULL DEFAULT 1.0,
            inVoiceLevel REAL NOT NULL DEFAULT 1.0,
            inBassLevel REAL NOT NULL DEFAULT 1.0,
            inInstrumentLevel REAL NOT NULL DEFAULT 1.0,
            PRIMARY KEY (playlistId, fromSongId, toSongId),
            FOREIGN KEY (playlistId) REFERENCES playlist(id) ON UPDATE NO ACTION ON DELETE CASCADE
        )
        """,
    ]

    public static let indexDDLStatements: [String] = [
        "CREATE INDEX IF NOT EXISTS index_song_albumId ON song(albumId)",
        "CREATE INDEX IF NOT EXISTS index_song_artist_map_songId ON song_artist_map(songId)",
        "CREATE INDEX IF NOT EXISTS index_song_artist_map_artistId ON song_artist_map(artistId)",
        "CREATE INDEX IF NOT EXISTS index_song_album_map_songId ON song_album_map(songId)",
        "CREATE INDEX IF NOT EXISTS index_song_album_map_albumId ON song_album_map(albumId)",
        "CREATE INDEX IF NOT EXISTS index_album_artist_map_albumId ON album_artist_map(albumId)",
        "CREATE INDEX IF NOT EXISTS index_album_artist_map_artistId ON album_artist_map(artistId)",
        "CREATE INDEX IF NOT EXISTS index_playlist_song_map_playlistId ON playlist_song_map(playlistId)",
        "CREATE INDEX IF NOT EXISTS index_playlist_song_map_songId ON playlist_song_map(songId)",
        "CREATE UNIQUE INDEX IF NOT EXISTS index_search_history_query ON search_history(query)",
        "CREATE INDEX IF NOT EXISTS index_event_songId ON event(songId)",
        "CREATE INDEX IF NOT EXISTS index_related_song_map_songId ON related_song_map(songId)",
        "CREATE INDEX IF NOT EXISTS index_related_song_map_relatedSongId ON related_song_map(relatedSongId)",
        "CREATE INDEX IF NOT EXISTS index_recognition_history_trackId ON recognition_history(trackId)",
        "CREATE INDEX IF NOT EXISTS index_playlist_event_playlistId ON playlist_event(playlistId)",
        "CREATE INDEX IF NOT EXISTS index_imported_song_source ON imported_song(source)",
        "CREATE INDEX IF NOT EXISTS index_import_session_song_songId ON import_session_song(songId)",
        "CREATE INDEX IF NOT EXISTS index_imported_playlist_source ON imported_playlist(source)",
        "CREATE INDEX IF NOT EXISTS index_playlist_transition_playlistId ON playlist_transition(playlistId)",
    ]

    public static let viewDDLStatements: [String] = [
        "CREATE VIEW IF NOT EXISTS sorted_song_artist_map AS SELECT * FROM song_artist_map ORDER BY position",
        "CREATE VIEW IF NOT EXISTS sorted_song_album_map AS SELECT * FROM song_album_map ORDER BY \"index\"",
        "CREATE VIEW IF NOT EXISTS playlist_song_map_preview AS SELECT * FROM playlist_song_map WHERE position <= 3 ORDER BY position",
    ]

    public static var v47DDLStatements: [String] {
        tableDDLStatements + indexDDLStatements + viewDDLStatements
    }
}
