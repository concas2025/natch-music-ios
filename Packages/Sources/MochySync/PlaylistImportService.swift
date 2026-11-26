import Foundation
import MochyCore
import MochyDatabase
import MochyInnerTube

public struct ImportProgressUpdate: Sendable, Equatable {
    public let stage: String
    public let matchedCount: Int
    public let totalCount: Int
}

public struct PlaylistImportResult: Sendable, Equatable {
    public let playlistId: String
    public let playlistName: String
    public let source: ExternalMusicService
    public let matchedCount: Int
    public let totalCount: Int
    public let failedTracks: [String]
}

public struct RawImportedTrack: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let durationSeconds: Int?
    public let isrc: String?

    public init(title: String, artist: String, durationSeconds: Int? = nil, isrc: String? = nil) {
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }
}

public enum PlaylistImportError: Error, LocalizedError {
    case unsupportedURL
    case emptyRemotePlaylist(String)
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "Unsupported playlist URL. Paste a public Spotify, Apple Music, or YouTube Music playlist link."
        case let .emptyRemotePlaylist(reason):
            return "Could not extract any tracks from playlist: \(reason)"
        case let .fetchFailed(reason):
            return "Failed to fetch remote playlist: \(reason)"
        }
    }
}

/// Real end-to-end public playlist importer modeled after `Lemielmusic/import_service.dart` & `Mochy-Music`:
/// - Spotify public playlists via `open.spotify.com/embed/playlist/{id}` `__NEXT_DATA__` (zero API keys)
/// - Apple Music public playlists via `<script type="application/ld+json">` + `<meta name="music:song">` fallback
/// - YouTube Music playlists via direct InnerTube `browsePlaylist("VL{id}")`
/// - Batched 4-way concurrent InnerTube matching via `TrackMatcher` -> persisted via `MochyDatabase.recordImportedPlaylist`
public actor PlaylistImportService {
    private static let webUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private let innerTube: InnerTubeClient
    private let database: MochyDatabase
    private let session: URLSession

    public init(
        innerTube: InnerTubeClient,
        database: MochyDatabase,
        session: URLSession? = nil
    ) {
        self.innerTube = innerTube
        self.database = database
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: cfg)
        }
    }

    public func importFromURL(
        _ urlString: String,
        onProgress: (@Sendable (ImportProgressUpdate) -> Void)? = nil
    ) async throws -> PlaylistImportResult {
        guard let target = LinkImporter.parse(urlString: urlString) else {
            throw PlaylistImportError.unsupportedURL
        }

        switch target.service {
        case .youtube:
            if target.kind == "playlist" {
                return try await importYouTubePlaylist(target: target, onProgress: onProgress)
            }
            return try await importSingleYouTubeTrack(videoId: target.remoteId, originalURL: target.originalURL)
        case .spotify:
            onProgress?(ImportProgressUpdate(stage: "Fetching Spotify playlist...", matchedCount: 0, totalCount: 0))
            let (name, rawTracks) = try await fetchSpotifyPublicTracks(kind: target.kind, remoteId: target.remoteId)
            return try await matchAndPersist(
                playlistName: name,
                rawTracks: rawTracks,
                source: .spotify,
                remoteId: target.remoteId,
                remoteUrl: target.originalURL.absoluteString,
                onProgress: onProgress
            )
        case .appleMusic:
            onProgress?(ImportProgressUpdate(stage: "Fetching Apple Music playlist...", matchedCount: 0, totalCount: 0))
            let (name, rawTracks) = try await fetchAppleMusicPublicTracks(url: target.originalURL)
            return try await matchAndPersist(
                playlistName: name,
                rawTracks: rawTracks,
                source: .appleMusic,
                remoteId: target.remoteId,
                remoteUrl: target.originalURL.absoluteString,
                onProgress: onProgress
            )
        case .tidal, .soundcloud:
            throw PlaylistImportError.fetchFailed("\(target.service.rawValue.capitalized) public scraping requires CSV export via TuneMyMusic / Exportify.")
        }
    }

    public func importFromCSV(
        csvText: String,
        playlistName: String = "Imported CSV Playlist",
        onProgress: (@Sendable (ImportProgressUpdate) -> Void)? = nil
    ) async throws -> PlaylistImportResult {
        let parsed = CsvImporter.parseTracks(csv: csvText)
        guard !parsed.isEmpty else {
            throw PlaylistImportError.emptyRemotePlaylist("CSV contained zero valid track rows.")
        }
        let rawTracks = parsed.map {
            RawImportedTrack(title: $0.title, artist: $0.artist, durationSeconds: $0.durationSeconds, isrc: $0.isrc)
        }
        return try await matchAndPersist(
            playlistName: playlistName,
            rawTracks: rawTracks,
            source: .spotify,
            remoteId: nil,
            remoteUrl: nil,
            onProgress: onProgress
        )
    }

    // MARK: - YouTube Direct Import

    private func importYouTubePlaylist(
        target: ImportedLinkTarget,
        onProgress: (@Sendable (ImportProgressUpdate) -> Void)?
    ) async throws -> PlaylistImportResult {
        onProgress?(ImportProgressUpdate(stage: "Fetching YouTube Music playlist...", matchedCount: 0, totalCount: 0))
        let collection = try await innerTube.browsePlaylist(playlistId: target.remoteId)
        guard !collection.tracks.isEmpty else {
            throw PlaylistImportError.emptyRemotePlaylist("No playable tracks found in YouTube playlist.")
        }

        let playlist = PlaylistEntity(
            name: collection.title,
            browseId: target.remoteId,
            thumbnailUrl: collection.thumbnailURL,
            isLocal: false
        )
        let dbSongs: [(song: SongEntity, artists: [ArtistEntity])] = collection.tracks.map { track in
            let song = SongEntity(
                id: track.id,
                title: track.title,
                duration: track.durationSeconds ?? -1,
                thumbnailUrl: track.thumbnailURL,
                albumName: track.album
            )
            let artists = track.artists.map { ArtistEntity(id: "yt-a-\($0.lowercased())", name: $0) }
            return (song, artists)
        }

        try database.recordImportedPlaylist(
            playlist: playlist,
            songs: dbSongs,
            source: ExternalMusicService.youtube.rawValue,
            remoteId: target.remoteId,
            remoteUrl: target.originalURL.absoluteString
        )
        onProgress?(ImportProgressUpdate(stage: "Done", matchedCount: dbSongs.count, totalCount: dbSongs.count))
        return PlaylistImportResult(
            playlistId: playlist.id,
            playlistName: playlist.name,
            source: .youtube,
            matchedCount: dbSongs.count,
            totalCount: dbSongs.count,
            failedTracks: []
        )
    }

    private func importSingleYouTubeTrack(videoId: String, originalURL: URL) async throws -> PlaylistImportResult {
        let resp = try await innerTube.player(client: .metadataClient, videoId: videoId)
        let title = resp.videoDetails?.title ?? "YouTube Track"
        let author = resp.videoDetails?.author ?? "Unknown Artist"
        let dur = resp.videoDetails.flatMap { Int($0.lengthSeconds) } ?? -1
        let thumb = resp.videoDetails?.thumbnail?.thumbnails.last?.url
        let song = SongEntity(id: videoId, title: title, duration: dur, thumbnailUrl: thumb)
        let artist = ArtistEntity(id: "yt-a-\(author.lowercased())", name: author)
        let playlist = PlaylistEntity(name: title, isLocal: true)
        try database.recordImportedPlaylist(
            playlist: playlist,
            songs: [(song, [artist])],
            source: ExternalMusicService.youtube.rawValue,
            remoteId: videoId,
            remoteUrl: originalURL.absoluteString
        )
        return PlaylistImportResult(
            playlistId: playlist.id,
            playlistName: playlist.name,
            source: .youtube,
            matchedCount: 1,
            totalCount: 1,
            failedTracks: []
        )
    }

    // MARK: - Spotify Public Embed Scraper (`__NEXT_DATA__`)

    private func fetchSpotifyPublicTracks(kind: String, remoteId: String) async throws -> (String, [RawImportedTrack]) {
        let embedKind = (kind == "album" || kind == "track") ? kind : "playlist"
        guard let url = URL(string: "https://open.spotify.com/embed/\(embedKind)/\(remoteId)") else {
            throw PlaylistImportError.unsupportedURL
        }
        var req = URLRequest(url: url)
        req.setValue(Self.webUA, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw PlaylistImportError.fetchFailed("Spotify embed returned HTTP error.")
        }
        guard let parsed = Self.parseSpotifyEmbedHTML(html), !parsed.tracks.isEmpty else {
            throw PlaylistImportError.emptyRemotePlaylist("Spotify playlist may be private or empty.")
        }
        return parsed
    }

    public static func parseSpotifyEmbedHTML(_ html: String) -> (name: String, tracks: [RawImportedTrack])? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]+id="\_\_NEXT\_DATA\_\_"[^>]*>([\s\S]*?)</script>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: nsRange),
              let jsonRange = Range(match.range(at: 1), in: html),
              let jsonData = String(html[jsonRange]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let entity = (((root["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["state"] as? [String: Any])
                .flatMap({ ($0["data"] as? [String: Any])?["entity"] as? [String: Any] }) else {
            return nil
        }

        let name = (entity["name"] as? String) ?? (entity["title"] as? String) ?? "Spotify Playlist"
        var tracks: [RawImportedTrack] = []
        if let list = entity["trackList"] as? [[String: Any]] {
            for row in list {
                guard let title = row["title"] as? String, !title.isEmpty else { continue }
                let subtitle = (row["subtitle"] as? String) ?? ""
                let durMs = row["duration"] as? Int
                tracks.append(
                    RawImportedTrack(
                        title: title,
                        artist: subtitle.replacingOccurrences(of: "\u{00A0}", with: " "),
                        durationSeconds: durMs.map { $0 / 1000 }
                    )
                )
            }
        } else if let title = entity["name"] as? String, !title.isEmpty {
            let artists = (entity["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let durMs = entity["duration"] as? Int
            tracks.append(RawImportedTrack(title: title, artist: artists, durationSeconds: durMs.map { $0 / 1000 }))
        }
        return (name, tracks)
    }

    // MARK: - Apple Music Public HTML Scraper (`application/ld+json` + meta fallback)

    private func fetchAppleMusicPublicTracks(url: URL) async throws -> (String, [RawImportedTrack]) {
        var req = URLRequest(url: url)
        req.setValue(Self.webUA, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw PlaylistImportError.fetchFailed("Apple Music page returned HTTP error.")
        }
        guard let parsed = Self.parseAppleMusicHTML(html), !parsed.tracks.isEmpty else {
            throw PlaylistImportError.emptyRemotePlaylist("Apple Music playlist may be private or empty.")
        }
        return parsed
    }

    public static func parseAppleMusicHTML(_ html: String) -> (name: String, tracks: [RawImportedTrack])? {
        if let ldRegex = try? NSRegularExpression(
            pattern: #"<script[^>]+type="application/ld\+json"[^>]*>([\s\S]*?)</script>"#,
            options: [.caseInsensitive]
        ) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in ldRegex.matches(in: html, range: nsRange) {
                guard let r = Range(match.range(at: 1), in: html),
                      let data = String(html[r]).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let trackArr = obj["track"] as? [[String: Any]], !trackArr.isEmpty else {
                    continue
                }
                let name = (obj["name"] as? String) ?? "Apple Music Playlist"
                let defaultArtist = ((obj["byArtist"] as? [String: Any])?["name"] as? String) ?? ""
                let tracks: [RawImportedTrack] = trackArr.compactMap { row in
                    guard let title = row["name"] as? String, !title.isEmpty else { return nil }
                    let artist: String
                    if let by = row["byArtist"] as? [String: Any], let n = by["name"] as? String {
                        artist = n
                    } else if let byArr = row["byArtist"] as? [[String: Any]] {
                        artist = byArr.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    } else {
                        artist = defaultArtist
                    }
                    return RawImportedTrack(title: title, artist: artist)
                }
                if !tracks.isEmpty {
                    return (name, tracks)
                }
            }
        }

        // Fallback: `<meta name="music:song" content="...">`
        guard let metaRegex = try? NSRegularExpression(
            pattern: #"<meta[^>]+name="music:song"[^>]+content="([^"]+)""#,
            options: [.caseInsensitive]
        ) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let tracks: [RawImportedTrack] = metaRegex.matches(in: html, range: nsRange).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            let raw = String(html[r])
            let slug = URL(string: raw)?.pathComponents.dropLast().last ?? raw
            let title = slug.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : RawImportedTrack(title: title, artist: "")
        }
        return tracks.isEmpty ? nil : ("Apple Music Playlist", tracks)
    }

    // MARK: - Concurrent Batched InnerTube Matching (4-way parallel)

    private func matchAndPersist(
        playlistName: String,
        rawTracks: [RawImportedTrack],
        source: ExternalMusicService,
        remoteId: String?,
        remoteUrl: String?,
        onProgress: (@Sendable (ImportProgressUpdate) -> Void)?
    ) async throws -> PlaylistImportResult {
        let total = rawTracks.count
        var matchedPairs: [(Int, SongEntity, [ArtistEntity])] = []
        var failedTitles: [String] = []
        var processed = 0

        let batchSize = 4
        var start = 0
        while start < total {
            let end = min(total, start + batchSize)
            let batchSlice = Array(start..<end)
            let batchResults = await withTaskGroup(of: (Int, YTTrackItem?).self) { group in
                for idx in batchSlice {
                    let raw = rawTracks[idx]
                    group.addTask { [innerTube] in
                        let q = "\(TrackMatcher.core(raw.title)) \(raw.artist)".trimmingCharacters(in: .whitespaces)
                        guard !q.isEmpty,
                              let hits = try? await innerTube.searchTracks(query: q),
                              !hits.isEmpty else {
                            return (idx, nil)
                        }
                        let candidates = hits.map {
                            TrackCandidate(
                                item: $0,
                                title: $0.title,
                                artist: $0.artistDisplay,
                                durationSeconds: $0.durationSeconds
                            )
                        }
                        let query = TrackQuery(
                            title: raw.title,
                            artist: raw.artist,
                            durationSeconds: raw.durationSeconds,
                            isrc: raw.isrc
                        )
                        if let best = TrackMatcher.bestMatch(query: query, candidates: candidates, threshold: 0.65) {
                            return (idx, best.candidate)
                        }
                        return (idx, hits.first)
                    }
                }
                var out: [(Int, YTTrackItem?)] = []
                for await pair in group { out.append(pair) }
                return out
            }

            for (idx, found) in batchResults {
                processed += 1
                if let yt = found {
                    let song = SongEntity(
                        id: yt.id,
                        title: yt.title,
                        duration: yt.durationSeconds ?? rawTracks[idx].durationSeconds ?? -1,
                        thumbnailUrl: yt.thumbnailURL,
                        albumName: yt.album
                    )
                    let artists = yt.artists.map { ArtistEntity(id: "yt-a-\($0.lowercased())", name: $0) }
                    matchedPairs.append((idx, song, artists))
                } else {
                    failedTitles.append("\(rawTracks[idx].title) — \(rawTracks[idx].artist)")
                }
                onProgress?(ImportProgressUpdate(
                    stage: "Matching \(processed)/\(total)...",
                    matchedCount: matchedPairs.count,
                    totalCount: total
                ))
            }
            start = end
        }

        let orderedSongs = matchedPairs.sorted { $0.0 < $1.0 }.map { (song: $0.1, artists: $0.2) }
        guard !orderedSongs.isEmpty else {
            throw PlaylistImportError.emptyRemotePlaylist("None of the \(total) tracks could be matched on YouTube Music.")
        }

        let playlist = PlaylistEntity(
            name: playlistName,
            thumbnailUrl: orderedSongs.first?.song.thumbnailUrl,
            isLocal: true
        )
        try database.recordImportedPlaylist(
            playlist: playlist,
            songs: orderedSongs,
            source: source.rawValue,
            remoteId: remoteId,
            remoteUrl: remoteUrl
        )
        onProgress?(ImportProgressUpdate(stage: "Completed", matchedCount: orderedSongs.count, totalCount: total))

        return PlaylistImportResult(
            playlistId: playlist.id,
            playlistName: playlist.name,
            source: source,
            matchedCount: orderedSongs.count,
            totalCount: total,
            failedTracks: failedTitles
        )
    }
}
