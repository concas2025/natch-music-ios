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
        let sections = try await innerTube.browseHome(browseId: "FEmusic_liked_videos")
        var trackCount = 0
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
                let artists = item.artists.enumerated().map { idx, name in
                    ArtistEntity(id: "yt-artist-\(name.lowercased())", name: name)
                }
                try database.upsertSong(song, artists: artists)
                trackCount += 1
            }
        }

        let skipped = excludeImportedPlaylists ? importedIds.count : 0
        return SyncSummary(importedTracks: trackCount, importedPlaylists: 0, skippedImportedPlaylists: skipped)
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
