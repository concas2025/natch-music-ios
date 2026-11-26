import Foundation
import MochyCore
import MochyDatabase
import MochyInnerTube

public struct SyncUndoSnapshot: Codable, Sendable, Equatable {
    public let createdAt: Date
    public let playlistIds: [String]
    public let likedSongIds: [String]
}

public struct SyncSummary: Sendable, Equatable {
    public let importedTracks: Int
    public let importedPlaylists: Int
    public let skippedImportedPlaylists: Int
}

/// Two-way YouTube Music library/playlist sync & undo controller (`SyncUtils.kt` + `YouTubeSyncManager.kt`).
public actor YouTubeSyncManager {
    private let innerTube: InnerTubeClient
    private let database: MochyDatabase
    private var lastUndoSnapshot: SyncUndoSnapshot?

    public init(innerTube: InnerTubeClient, database: MochyDatabase) {
        self.innerTube = innerTube
        self.database = database
    }

    public func isSignedIn() async -> Bool {
        let cookie = await innerTube.cookie
        return !(cookie?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public func syncLibrary(excludeImportedPlaylists: Bool = true) async throws -> SyncSummary {
        guard await isSignedIn() else {
            return SyncSummary(importedTracks: 0, importedPlaylists: 0, skippedImportedPlaylists: 0)
        }

        // Capture undo snapshot before mutating local DB
        let existingPlaylists = try database.fetchPlaylists().map(\.id)
        let existingLiked = try database.fetchLikedSongs().map(\.id)
        lastUndoSnapshot = SyncUndoSnapshot(
            createdAt: Date(),
            playlistIds: existingPlaylists,
            likedSongIds: existingLiked
        )

        let importedIds = try database.fetchImportedPlaylistIds()
        var trackCount = 0
        var playlistCount = 0

        // 1. Sync Liked Songs (`FEmusic_liked_videos`) WITH authenticated headers (`setLogin: true`)!
        let sections = try await innerTube.browseHome(browseId: "FEmusic_liked_videos", setLogin: true)
        for section in sections {
            for item in section.items {
                let song = SongEntity(
                    id: item.id,
                    title: item.title,
                    duration: item.durationSeconds ?? -1,
                    thumbnailUrl: item.thumbnailURL,
                    albumName: item.album,
                    liked: true,
                    likedDate: Int64(Date().timeIntervalSince1970 * 1000)
                )
                let artists = item.artists.map { name in
                    ArtistEntity(id: "yt-a-\(name.lowercased())", name: name)
                }
                try database.upsertSong(song, artists: artists)
                trackCount += 1
            }
        }

        // 2. Sync User YouTube Music Playlists (`FEmusic_liked_playlists`)
        let remotePlaylists = (try? await innerTube.browseLibraryPlaylists()) ?? []
        for plSummary in remotePlaylists {
            if excludeImportedPlaylists && importedIds.contains(plSummary.id) {
                continue
            }
            let plEntity = PlaylistEntity(
                id: plSummary.id,
                name: plSummary.title,
                browseId: plSummary.id,
                thumbnailUrl: plSummary.thumbnailURL,
                isLocal: false,
                isAutoSync: true
            )
            try database.upsertPlaylist(plEntity)
            playlistCount += 1

            if let detail = try? await innerTube.browsePlaylist(playlistId: plSummary.id, setLogin: true),
               !detail.tracks.isEmpty {
                var songIds: [String] = []
                for track in detail.tracks {
                    let song = SongEntity(
                        id: track.id,
                        title: track.title,
                        duration: track.durationSeconds ?? -1,
                        thumbnailUrl: track.thumbnailURL,
                        albumName: track.album
                    )
                    let artists = track.artists.map { ArtistEntity(id: "yt-a-\($0.lowercased())", name: $0) }
                    try database.upsertSong(song, artists: artists)
                    songIds.append(track.id)
                    trackCount += 1
                }
                try database.replacePlaylistSongs(playlistId: plEntity.id, songIds: songIds)
            }
        }

        let skipped = excludeImportedPlaylists ? importedIds.count : 0
        return SyncSummary(importedTracks: trackCount, importedPlaylists: playlistCount, skippedImportedPlaylists: skipped)
    }

    /// Reverts the most recent YouTube Music library sync back to the captured `SyncUndoSnapshot`.
    @discardableResult
    public func undoLastSync() throws -> Bool {
        guard let snap = lastUndoSnapshot else { return false }
        try database.restoreSyncSnapshot(
            keepPlaylistIds: Set(snap.playlistIds),
            likedSongIds: Set(snap.likedSongIds)
        )
        lastUndoSnapshot = nil
        return true
    }

    public func setRemoteLikeStatus(videoId: String, liked: Bool) async throws {
        guard await isSignedIn() else { return }
        struct LikeBody: Encodable {
            let context: InnerTubeContext
            let target: [String: String]
        }
        let client = YouTubeClient.metadataClient
        let visitor = await innerTube.visitorData
        let dataSync = await innerTube.dataSyncId
        let body = LikeBody(
            context: client.toContext(locale: YouTubeLocale(), visitorData: visitor, dataSyncId: dataSync),
            target: ["videoId": videoId]
        )
        _ = try await innerTube.rawPost(
            endpoint: liked ? "like/like" : "like/removelike",
            client: client,
            body: body,
            setLogin: true
        )
    }

    public func latestUndoSnapshot() -> SyncUndoSnapshot? {
        lastUndoSnapshot
    }
}
