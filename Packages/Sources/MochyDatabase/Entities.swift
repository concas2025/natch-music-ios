import Foundation
import GRDB

public struct SongEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable, Identifiable {
    public static let databaseTableName = "song"

    public var id: String
    public var title: String
    public var duration: Int
    public var thumbnailUrl: String?
    public var albumId: String?
    public var albumName: String?
    public var explicit: Bool
    public var year: Int?
    public var date: Int64?
    public var dateModified: Int64?
    public var liked: Bool
    public var likedDate: Int64?
    public var totalPlayTime: Int64
    public var inLibrary: Int64?
    public var dateDownload: Int64?
    public var isLocal: Bool
    public var libraryAddToken: String?
    public var libraryRemoveToken: String?
    public var lyricsOffset: Int
    public var romanizeLyrics: Bool
    public var isDownloaded: Bool
    public var isUploaded: Bool
    public var isVideo: Bool
    public var localUri: String?
    public var addedByLike: Bool
    public var genre: String?

    public init(
        id: String,
        title: String,
        duration: Int = -1,
        thumbnailUrl: String? = nil,
        albumId: String? = nil,
        albumName: String? = nil,
        explicit: Bool = false,
        year: Int? = nil,
        date: Int64? = nil,
        dateModified: Int64? = nil,
        liked: Bool = false,
        likedDate: Int64? = nil,
        totalPlayTime: Int64 = 0,
        inLibrary: Int64? = nil,
        dateDownload: Int64? = nil,
        isLocal: Bool = false,
        libraryAddToken: String? = nil,
        libraryRemoveToken: String? = nil,
        lyricsOffset: Int = 0,
        romanizeLyrics: Bool = true,
        isDownloaded: Bool = false,
        isUploaded: Bool = false,
        isVideo: Bool = false,
        localUri: String? = nil,
        addedByLike: Bool = false,
        genre: String? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.thumbnailUrl = thumbnailUrl
        self.albumId = albumId
        self.albumName = albumName
        self.explicit = explicit
        self.year = year
        self.date = date
        self.dateModified = dateModified
        self.liked = liked
        self.likedDate = likedDate
        self.totalPlayTime = totalPlayTime
        self.inLibrary = inLibrary
        self.dateDownload = dateDownload
        self.isLocal = isLocal
        self.libraryAddToken = libraryAddToken
        self.libraryRemoveToken = libraryRemoveToken
        self.lyricsOffset = lyricsOffset
        self.romanizeLyrics = romanizeLyrics
        self.isDownloaded = isDownloaded
        self.isUploaded = isUploaded
        self.isVideo = isVideo
        self.localUri = localUri
        self.addedByLike = addedByLike
        self.genre = genre
    }
}

public struct ArtistEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "artist"

    public var id: String
    public var name: String
    public var thumbnailUrl: String?
    public var channelId: String?
    public var lastUpdateTime: Int64
    public var bookmarkedAt: Int64?
    public var isLocal: Bool

    public init(
        id: String,
        name: String,
        thumbnailUrl: String? = nil,
        channelId: String? = nil,
        lastUpdateTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        bookmarkedAt: Int64? = nil,
        isLocal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.channelId = channelId
        self.lastUpdateTime = lastUpdateTime
        self.bookmarkedAt = bookmarkedAt
        self.isLocal = isLocal
    }
}

public struct AlbumEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "album"

    public var id: String
    public var playlistId: String?
    public var title: String
    public var year: Int?
    public var thumbnailUrl: String?
    public var themeColor: Int?
    public var songCount: Int
    public var duration: Int
    public var explicit: Bool
    public var lastUpdateTime: Int64
    public var bookmarkedAt: Int64?
    public var likedDate: Int64?
    public var inLibrary: Int64?
    public var description: String?
    public var isLocal: Bool
    public var isUploaded: Bool

    public init(
        id: String,
        playlistId: String? = nil,
        title: String,
        year: Int? = nil,
        thumbnailUrl: String? = nil,
        themeColor: Int? = nil,
        songCount: Int = 0,
        duration: Int = 0,
        explicit: Bool = false,
        lastUpdateTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        bookmarkedAt: Int64? = nil,
        likedDate: Int64? = nil,
        inLibrary: Int64? = nil,
        description: String? = nil,
        isLocal: Bool = false,
        isUploaded: Bool = false
    ) {
        self.id = id
        self.playlistId = playlistId
        self.title = title
        self.year = year
        self.thumbnailUrl = thumbnailUrl
        self.themeColor = themeColor
        self.songCount = songCount
        self.duration = duration
        self.explicit = explicit
        self.lastUpdateTime = lastUpdateTime
        self.bookmarkedAt = bookmarkedAt
        self.likedDate = likedDate
        self.inLibrary = inLibrary
        self.description = description
        self.isLocal = isLocal
        self.isUploaded = isUploaded
    }
}

public struct PlaylistEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "playlist"

    public var id: String
    public var name: String
    public var browseId: String?
    public var createdAt: Int64?
    public var lastUpdateTime: Int64?
    public var isEditable: Bool
    public var bookmarkedAt: Int64?
    public var remoteSongCount: Int?
    public var playEndpointParams: String?
    public var thumbnailUrl: String?
    public var shuffleEndpointParams: String?
    public var radioEndpointParams: String?
    public var isLocal: Bool
    public var isAutoSync: Bool
    public var description: String?
    public var mixItEnabled: Bool
    public var mixItFallback: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        browseId: String? = nil,
        createdAt: Int64? = Int64(Date().timeIntervalSince1970 * 1000),
        lastUpdateTime: Int64? = Int64(Date().timeIntervalSince1970 * 1000),
        isEditable: Bool = true,
        bookmarkedAt: Int64? = nil,
        remoteSongCount: Int? = nil,
        playEndpointParams: String? = nil,
        thumbnailUrl: String? = nil,
        shuffleEndpointParams: String? = nil,
        radioEndpointParams: String? = nil,
        isLocal: Bool = false,
        isAutoSync: Bool = false,
        description: String? = nil,
        mixItEnabled: Bool = false,
        mixItFallback: String? = nil
    ) {
        self.id = id
        self.name = name
        self.browseId = browseId
        self.createdAt = createdAt
        self.lastUpdateTime = lastUpdateTime
        self.isEditable = isEditable
        self.bookmarkedAt = bookmarkedAt
        self.remoteSongCount = remoteSongCount
        self.playEndpointParams = playEndpointParams
        self.thumbnailUrl = thumbnailUrl
        self.shuffleEndpointParams = shuffleEndpointParams
        self.radioEndpointParams = radioEndpointParams
        self.isLocal = isLocal
        self.isAutoSync = isAutoSync
        self.description = description
        self.mixItEnabled = mixItEnabled
        self.mixItFallback = mixItFallback
    }
}

public struct SongArtistMap: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "song_artist_map"
    public var songId: String
    public var artistId: String
    public var position: Int

    public init(songId: String, artistId: String, position: Int) {
        self.songId = songId
        self.artistId = artistId
        self.position = position
    }
}

public struct SongAlbumMap: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "song_album_map"
    public var songId: String
    public var albumId: String
    public var index: Int

    public init(songId: String, albumId: String, index: Int) {
        self.songId = songId
        self.albumId = albumId
        self.index = index
    }
}

public struct AlbumArtistMap: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "album_artist_map"
    public var albumId: String
    public var artistId: String
    public var order: Int

    public init(albumId: String, artistId: String, order: Int) {
        self.albumId = albumId
        self.artistId = artistId
        self.order = order
    }
}

public struct PlaylistSongMap: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "playlist_song_map"
    public var id: Int64?
    public var playlistId: String
    public var songId: String
    public var position: Int
    public var setVideoId: String?

    public init(id: Int64? = nil, playlistId: String, songId: String, position: Int = 0, setVideoId: String? = nil) {
        self.id = id
        self.playlistId = playlistId
        self.songId = songId
        self.position = position
        self.setVideoId = setVideoId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SearchHistoryEntry: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "search_history"
    public var id: Int64?
    public var query: String

    public init(id: Int64? = nil, query: String) {
        self.id = id
        self.query = query
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct FormatEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "format"

    public var id: String
    public var itag: Int
    public var mimeType: String
    public var codecs: String
    public var bitrate: Int
    public var sampleRate: Int?
    public var contentLength: Int64
    public var loudnessDb: Double?
    public var perceptualLoudnessDb: Double?
    public var playbackUrl: String?

    public init(
        id: String,
        itag: Int,
        mimeType: String,
        codecs: String,
        bitrate: Int,
        sampleRate: Int? = nil,
        contentLength: Int64 = 0,
        loudnessDb: Double? = nil,
        perceptualLoudnessDb: Double? = nil,
        playbackUrl: String? = nil
    ) {
        self.id = id
        self.itag = itag
        self.mimeType = mimeType
        self.codecs = codecs
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.contentLength = contentLength
        self.loudnessDb = loudnessDb
        self.perceptualLoudnessDb = perceptualLoudnessDb
        self.playbackUrl = playbackUrl
    }
}

public struct LyricsEntity: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "lyrics"

    public var id: String
    public var lyrics: String
    public var provider: String
    public var translatedLyrics: String
    public var translationLanguage: String
    public var translationMode: String

    public init(
        id: String,
        lyrics: String,
        provider: String = "Unknown",
        translatedLyrics: String = "",
        translationLanguage: String = "",
        translationMode: String = ""
    ) {
        self.id = id
        self.lyrics = lyrics
        self.provider = provider
        self.translatedLyrics = translatedLyrics
        self.translationLanguage = translationLanguage
        self.translationMode = translationMode
    }
}

public struct EventEntity: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "event"
    public var id: Int64?
    public var songId: String
    public var timestamp: Int64
    public var playTime: Int64

    public init(id: Int64? = nil, songId: String, timestamp: Int64, playTime: Int64) {
        self.id = id
        self.songId = songId
        self.timestamp = timestamp
        self.playTime = playTime
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct RelatedSongMap: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "related_song_map"
    public var id: Int64?
    public var songId: String
    public var relatedSongId: String

    public init(id: Int64? = nil, songId: String, relatedSongId: String) {
        self.id = id
        self.songId = songId
        self.relatedSongId = relatedSongId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SpeedDialItem: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "speed_dial_item"

    public var id: String
    public var secondaryId: String?
    public var title: String
    public var subtitle: String?
    public var thumbnailUrl: String?
    public var type: String
    public var explicit: Bool
    public var createDate: Int64

    public init(
        id: String,
        secondaryId: String? = nil,
        title: String,
        subtitle: String? = nil,
        thumbnailUrl: String? = nil,
        type: String,
        explicit: Bool = false,
        createDate: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.secondaryId = secondaryId
        self.title = title
        self.subtitle = subtitle
        self.thumbnailUrl = thumbnailUrl
        self.type = type
        self.explicit = explicit
        self.createDate = createDate
    }
}

public struct SongEdit: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "song_edit"

    public var songId: String
    public var title: String?
    public var artists: String?
    public var album: String?
    public var year: Int?
    public var cover: String?
    public var videoId: String?
    public var noVideo: Bool

    public init(
        songId: String,
        title: String? = nil,
        artists: String? = nil,
        album: String? = nil,
        year: Int? = nil,
        cover: String? = nil,
        videoId: String? = nil,
        noVideo: Bool = false
    ) {
        self.songId = songId
        self.title = title
        self.artists = artists
        self.album = album
        self.year = year
        self.cover = cover
        self.videoId = videoId
        self.noVideo = noVideo
    }
}

public struct PlaylistTransition: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "playlist_transition"

    public var playlistId: String
    public var fromSongId: String
    public var toSongId: String
    public var outStartMs: Int64
    public var inStartMs: Int64
    public var durationMs: Int64
    public var outEffect: String?
    public var inEffect: String?
    public var outFadeStart: Double?
    public var outFadeEnd: Double?
    public var inFadeStart: Double?
    public var inFadeEnd: Double?
    public var beatMatchMode: String?
    public var snapToBeat: Bool?
    public var bassSwap: Bool?
    public var swapFrac: Double?
    public var beatNudgeMs: Int64?
    public var customSpeedRatio: Double?
    public var presetName: String?
    public var updatedAt: Int64
    public var outVoiceLevel: Double
    public var outBassLevel: Double
    public var outInstrumentLevel: Double
    public var inVoiceLevel: Double
    public var inBassLevel: Double
    public var inInstrumentLevel: Double

    public init(
        playlistId: String,
        fromSongId: String,
        toSongId: String,
        outStartMs: Int64,
        inStartMs: Int64,
        durationMs: Int64,
        outEffect: String? = nil,
        inEffect: String? = nil,
        outFadeStart: Double? = nil,
        outFadeEnd: Double? = nil,
        inFadeStart: Double? = nil,
        inFadeEnd: Double? = nil,
        beatMatchMode: String? = nil,
        snapToBeat: Bool? = nil,
        bassSwap: Bool? = nil,
        swapFrac: Double? = nil,
        beatNudgeMs: Int64? = nil,
        customSpeedRatio: Double? = nil,
        presetName: String? = nil,
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        outVoiceLevel: Double = 1.0,
        outBassLevel: Double = 1.0,
        outInstrumentLevel: Double = 1.0,
        inVoiceLevel: Double = 1.0,
        inBassLevel: Double = 1.0,
        inInstrumentLevel: Double = 1.0
    ) {
        self.playlistId = playlistId
        self.fromSongId = fromSongId
        self.toSongId = toSongId
        self.outStartMs = outStartMs
        self.inStartMs = inStartMs
        self.durationMs = durationMs
        self.outEffect = outEffect
        self.inEffect = inEffect
        self.outFadeStart = outFadeStart
        self.outFadeEnd = outFadeEnd
        self.inFadeStart = inFadeStart
        self.inFadeEnd = inFadeEnd
        self.beatMatchMode = beatMatchMode
        self.snapToBeat = snapToBeat
        self.bassSwap = bassSwap
        self.swapFrac = swapFrac
        self.beatNudgeMs = beatNudgeMs
        self.customSpeedRatio = customSpeedRatio
        self.presetName = presetName
        self.updatedAt = updatedAt
        self.outVoiceLevel = outVoiceLevel
        self.outBassLevel = outBassLevel
        self.outInstrumentLevel = outInstrumentLevel
        self.inVoiceLevel = inVoiceLevel
        self.inBassLevel = inBassLevel
        self.inInstrumentLevel = inInstrumentLevel
    }
}
