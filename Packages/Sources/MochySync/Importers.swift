import Foundation
import MochyCore
import MochyDatabase

// MARK: - Link Importer (Spotify / Apple Music / Tidal / SoundCloud / YouTube)

public enum ExternalMusicService: String, Codable, Sendable, Equatable {
    case spotify
    case appleMusic
    case tidal
    case soundcloud
    case youtube
}

public struct ImportedLinkTarget: Sendable, Equatable {
    public let service: ExternalMusicService
    public let kind: String // "playlist", "album", "track"
    public let remoteId: String
    public let originalURL: URL
}

public enum LinkImporter {
    public static func parse(urlString: String) -> ImportedLinkTarget? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else {
            return nil
        }

        let path = url.pathComponents.filter { $0 != "/" }
        if host.contains("spotify.com"), path.count >= 2 {
            return ImportedLinkTarget(service: .spotify, kind: path[0], remoteId: path[1], originalURL: url)
        }
        if host.contains("music.apple.com"), path.count >= 3 {
            let kind = path[1]
            let remoteId = path.last ?? ""
            return ImportedLinkTarget(service: .appleMusic, kind: kind, remoteId: remoteId, originalURL: url)
        }
        if host.contains("tidal.com"), path.count >= 2 {
            let clean = path.filter { $0 != "browse" }
            if clean.count >= 2 {
                return ImportedLinkTarget(service: .tidal, kind: clean[0], remoteId: clean[1], originalURL: url)
            }
        }
        if host.contains("soundcloud.com"), !path.isEmpty {
            let kind = path.contains("sets") ? "playlist" : "track"
            return ImportedLinkTarget(service: .soundcloud, kind: kind, remoteId: path.joined(separator: "/"), originalURL: url)
        }
        if host.contains("youtube.com") || host.contains("youtu.be") {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let listId = comps?.queryItems?.first(where: { $0.name == "list" })?.value {
                return ImportedLinkTarget(service: .youtube, kind: "playlist", remoteId: listId, originalURL: url)
            }
            if let vId = comps?.queryItems?.first(where: { $0.name == "v" })?.value ?? (host.contains("youtu.be") ? path.first : nil) {
                return ImportedLinkTarget(service: .youtube, kind: "track", remoteId: vId, originalURL: url)
            }
        }
        return nil
    }
}

// MARK: - RFC4180 CSV Importer & Exporter

public struct ImportedCSVTrack: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let album: String?
    public let isrc: String?
    public let durationSeconds: Int?
}

public enum CsvImporter {
    public static func parseTracks(csv: String) -> [ImportedCSVTrack] {
        let rows = parseRows(csv: csv)
        guard let header = rows.first, !header.isEmpty else { return [] }

        let lowered = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let titleIdx = lowered.firstIndex(where: { $0.contains("title") || $0.contains("track name") || $0 == "name" }) ?? 0
        let artistIdx = lowered.firstIndex(where: { $0.contains("artist") }) ?? min(1, lowered.count - 1)
        let albumIdx = lowered.firstIndex(where: { $0.contains("album") })
        let isrcIdx = lowered.firstIndex(where: { $0.contains("isrc") })
        let durIdx = lowered.firstIndex(where: { $0.contains("duration") || $0.contains("length") })

        return rows.dropFirst().compactMap { cols in
            guard cols.count > max(titleIdx, artistIdx) else { return nil }
            let title = cols[titleIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = cols[artistIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let album = albumIdx.flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            let isrc = isrcIdx.flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            let durRaw = durIdx.flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            let dur = durRaw.flatMap(Int.init).map { $0 > 1000 ? $0 / 1000 : $0 }
            return ImportedCSVTrack(
                title: title,
                artist: artist,
                album: album?.isEmpty == true ? nil : album,
                isrc: isrc?.isEmpty == true ? nil : isrc,
                durationSeconds: dur
            )
        }
    }

    public static func exportCSV(songs: [(song: SongEntity, artists: String)]) -> String {
        var lines = ["Track Name,Artist Name,Album Name,Duration Seconds,ID"]
        for entry in songs {
            let fields = [
                escape(entry.song.title),
                escape(entry.artists),
                escape(entry.song.albumName ?? ""),
                String(max(0, entry.song.duration)),
                escape(entry.song.id),
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func parseRows(csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(csv.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                row.append(current)
                current = ""
            } else if ch == "\n" && !inQuotes {
                row.append(current)
                rows.append(row)
                row = []
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        if !current.isEmpty || !row.isEmpty {
            row.append(current)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Portable Transfer Archive (JSON Snapshot of Songs, Playlists, Edits, Transitions)

public struct TransferArchivePayload: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let songs: [SongEntity]
    public let artists: [ArtistEntity]?
    public let songArtistMaps: [SongArtistMap]?
    public let albums: [AlbumEntity]?
    public let playlists: [PlaylistEntity]
    public let playlistSongMaps: [PlaylistSongMap]?
    public let songEdits: [SongEdit]
    public let transitions: [PlaylistTransition]
    public let speedDial: [SpeedDialItem]
}

public enum TransferArchive {
    public static func exportJSON(from database: MochyDatabase) throws -> Data {
        let payload = TransferArchivePayload(
            schemaVersion: MochyDatabaseSchema.version,
            exportedAt: Date(),
            songs: try database.fetchAllSongs(),
            artists: try database.fetchArtists(),
            songArtistMaps: try database.fetchAllSongArtistMaps(),
            albums: try database.fetchAlbums(),
            playlists: try database.fetchPlaylists(),
            playlistSongMaps: try database.fetchAllPlaylistSongMaps(),
            songEdits: try database.fetchAllSongEdits(),
            transitions: try database.fetchAllTransitions(),
            speedDial: try database.fetchSpeedDialItems()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func importJSON(_ data: Data, into database: MochyDatabase) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(TransferArchivePayload.self, from: data)
        for song in payload.songs { try database.upsertSong(song) }
        for artist in payload.artists ?? [] { try database.upsertArtist(artist) }
        for map in payload.songArtistMaps ?? [] { try? database.upsertSongArtistMap(map) }
        for album in payload.albums ?? [] { try database.upsertAlbum(album) }
        for playlist in payload.playlists { try database.upsertPlaylist(playlist) }
        if let plMaps = payload.playlistSongMaps, !plMaps.isEmpty {
            let grouped = Dictionary(grouping: plMaps, by: \.playlistId)
            for (pid, rows) in grouped {
                let orderedSongIds = rows.sorted { $0.position < $1.position }.map(\.songId)
                try? database.replacePlaylistSongs(playlistId: pid, songIds: orderedSongIds)
            }
        }
        for edit in payload.songEdits { try database.upsertSongEdit(edit) }
        for tr in payload.transitions { try? database.upsertTransition(tr) }
        for sd in payload.speedDial { try database.pinToSpeedDial(sd) }
        return payload.songs.count
    }
}
