import Foundation
import MochyCore

public struct FlacStreamInfo: Sendable, Equatable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int

    public var isHiRes: Bool {
        sampleRate > 48_000 || bitsPerSample > 16
    }

    public var qualityBadge: String {
        let rateKHz = sampleRate % 1000 == 0
            ? "\(sampleRate / 1000)"
            : String(format: "%.1f", Double(sampleRate) / 1000.0)
        return isHiRes
            ? "Hi-Res FLAC · \(bitsPerSample)-bit / \(rateKHz) kHz"
            : "FLAC · \(bitsPerSample)-bit / \(rateKHz) kHz"
    }
}

/// Parses FLAC `fLaC` + `STREAMINFO` header bytes (`bytes 0...25`).
public enum FlacStreamInfoParser {
    public static func parse(_ data: Data) -> FlacStreamInfo? {
        guard data.count >= 22 else { return nil }
        let bytes = [UInt8](data.prefix(26))
        guard bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else {
            return nil
        }
        guard (bytes[4] & 0x7F) == 0 else { return nil }

        let b18 = UInt32(bytes[18])
        let b19 = UInt32(bytes[19])
        let b20 = UInt32(bytes[20])
        let b21 = UInt32(bytes[21])

        let sampleRate = Int((b18 << 12) | (b19 << 4) | (b20 >> 4))
        let channels = Int(((b20 >> 1) & 0x07) + 1)
        let bitsPerSample = Int((((b20 & 0x01) << 4) | (b21 >> 4)) + 1)

        guard sampleRate > 0, channels > 0, bitsPerSample >= 4 else { return nil }
        return FlacStreamInfo(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
    }
}

/// Lossless FLAC / Hi-Res FLAC source module matching `realidkroo/Mochy-Music`'s `MonochromeModule.kt` schema:
/// parses `"trackId"`/`"id"`, `"artistNames": [String]`, millisecond `"duration"`, `"playable"`, and custom servers.
public actor MonochromeModule: MochyStreamModule {
    public enum ServerKind: String, Codable, Sendable {
        case streamer
        case relay
    }

    public struct Server: Codable, Sendable, Equatable, Identifiable {
        public let url: URL
        public let kind: ServerKind
        public let name: String
        public var id: String { url.absoluteString }

        public init(url: URL, kind: ServerKind = .streamer, name: String? = nil) {
            self.url = url
            self.kind = kind
            self.name = name ?? url.host ?? url.absoluteString
        }
    }

    public nonisolated let id = "monochrome"
    public nonisolated let displayName = "Monochrome FLAC"
    public nonisolated let supportsDownload = true

    public static let defaultBaseURL = URL(string: "https://tracks.monochrome.st")!
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    private static let missMemorySeconds: TimeInterval = 30 * 60
    private static let unreachableRetrySeconds: TimeInterval = 10 * 60

    private let builtInServer: Server
    private var customServers: [Server]
    private let session: URLSession
    private var matchCache: [String: String] = [:]
    private var missCache: [String: Date] = [:]
    private var unreachableUntilByServer: [String: Date] = [:]

    public init(
        baseURL: URL = MonochromeModule.defaultBaseURL,
        serverKind: ServerKind = .streamer,
        customServers: [Server] = [],
        session: URLSession? = nil
    ) {
        self.builtInServer = Server(url: baseURL, kind: serverKind)
        self.customServers = customServers
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 8
            cfg.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: cfg)
        }
    }

    public func setCustomServers(_ urls: [String]) {
        self.customServers = urls.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            guard let url = URL(string: normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                  ModuleUrlGuard.isAllowedPublicURL(url) else { return nil }
            let kind: ServerKind = url.host?.lowercased().contains("relay") == true ? .relay : .streamer
            return Server(url: url, kind: kind)
        }
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        let allServers = customServers + [builtInServer]
        let now = Date()
        let activeServers = allServers.filter { (unreachableUntilByServer[$0.id] ?? .distantPast) <= now }
        let serversToTry = activeServers.isEmpty ? allServers : activeServers

        for server in serversToTry {
            if let stream = try await resolveOn(server: server, track: track) {
                return stream
            }
        }
        return nil
    }

    private func resolveOn(server: Server, track: ModuleTrack) async throws -> ModuleStream? {
        let cacheKey = "\(server.id)|\(track.id)|\(track.title)|\(track.artist)"
        if let missedAt = missCache[cacheKey], Date().timeIntervalSince(missedAt) < Self.missMemorySeconds {
            return nil
        }

        let matchedId: String
        if let cached = matchCache[cacheKey] {
            matchedId = cached
        } else {
            let primaryArtist = track.artist.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? track.artist
            let queryText = "\(primaryArtist) \(TrackMatcher.core(track.title))".trimmingCharacters(in: .whitespaces)
            guard let foundId = try await searchBestTrackId(server: server, track: track, queryText: queryText) else {
                missCache[cacheKey] = Date()
                return nil
            }
            matchCache[cacheKey] = foundId
            matchedId = foundId
        }

        guard let opened = try await openAndProbeFlac(server: server, matchedId: matchedId) else {
            return nil
        }

        guard ModuleUrlGuard.isAllowedPublicURL(opened.url),
              let info = FlacStreamInfoParser.parse(opened.headBytes),
              info.sampleRate <= 192_000 else {
            return nil
        }

        return ModuleStream(
            url: opened.url,
            headers: ["User-Agent": Self.userAgent],
            format: .progressive,
            codec: "FLAC",
            mimeType: "audio/flac",
            contentLength: opened.contentLength,
            durationSeconds: track.durationSeconds,
            sampleRate: info.sampleRate,
            bitDepth: info.bitsPerSample,
            bitrate: info.sampleRate * info.channels * info.bitsPerSample,
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: info.qualityBadge,
            isDRM: false
        )
    }

    private func searchBestTrackId(server: Server, track: ModuleTrack, queryText: String) async throws -> String? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let encoded = queryText.addingPercentEncoding(withAllowedCharacters: allowed) ?? queryText
        let baseStr = server.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString: String
        switch server.kind {
        case .streamer:
            urlString = "\(baseStr)/search/tracks?q=\(encoded)&limit=8"
        case .relay:
            urlString = "\(baseStr)/search?q=\(encoded)&n=8"
        }
        guard let url = URL(string: urlString), ModuleUrlGuard.isAllowedPublicURL(url) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if server.kind == .relay {
            req.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            unreachableUntilByServer[server.id] = Date().addingTimeInterval(Self.unreachableRetrySeconds)
            return nil
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let candidates = Self.parseSearchCandidates(from: json, kind: server.kind)
        let query = TrackQuery(
            title: track.title,
            artist: track.artist,
            durationSeconds: track.durationSeconds,
            isrc: track.isrc
        )
        return TrackMatcher.bestMatch(query: query, candidates: candidates)?.candidate
    }

    /// Parses both Monochrome Streamer (`tracks[]` with `trackId`, `artistNames`, ms `duration`)
    /// and Relay (`data[]` with `id`, `artist` separated by `&`) JSON payloads.
    public static func parseSearchCandidates(from json: [String: Any], kind: ServerKind) -> [TrackCandidate<String>] {
        let listKey = kind == .streamer ? "tracks" : "data"
        guard let items = json[listKey] as? [[String: Any]] else { return [] }

        return items.compactMap { row -> TrackCandidate<String>? in
            if let playable = row["playable"] as? Bool, !playable {
                return nil
            }
            let itemId: String? =
                (row["trackId"] as? String)
                ?? (row["id"] as? String)
                ?? (row["trackId"] as? Int).map(String.init)
                ?? (row["id"] as? Int).map(String.init)
            guard let id = itemId, !id.isEmpty,
                  let title = row["title"] as? String, !title.isEmpty else {
                return nil
            }

            let artist: String
            if let names = row["artistNames"] as? [String], !names.isEmpty {
                artist = names.joined(separator: ", ")
            } else if let objs = row["artists"] as? [[String: Any]] {
                artist = objs.compactMap { $0["name"] as? String }.joined(separator: ", ")
            } else if let rawArtist = row["artist"] as? String {
                // Relay joins multiple artists with bare `&` without spaces.
                artist = rawArtist.replacingOccurrences(of: #"(?<! )&(?! )"#, with: ", ", options: .regularExpression)
            } else {
                artist = ""
            }

            let rawDur: Int? =
                (row["duration"] as? Int)
                ?? (row["durationMs"] as? Int)
                ?? (row["duration"] as? String).flatMap(Int.init)
            // Streamer reports duration in milliseconds (> 10_000); normalize to seconds.
            let durSec = rawDur.map { $0 > 10_000 ? $0 / 1000 : $0 }
            let isrc = row["isrc"] as? String

            return TrackCandidate(item: id, title: title, artist: artist, durationSeconds: durSec, isrc: isrc)
        }
    }

    private func openAndProbeFlac(server: Server, matchedId: String) async throws -> (url: URL, headBytes: Data, contentLength: Int64?)? {
        let baseStr = server.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch server.kind {
        case .streamer:
            guard let url = URL(string: "\(baseStr)/track/\(matchedId)") else { return nil }
            var req = URLRequest(url: url)
            req.setValue("bytes=0-41", forHTTPHeaderField: "Range")
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206) else {
                return nil
            }
            let total = parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range"))
            return (url, data, total)
        case .relay:
            let encId = matchedId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? matchedId
            guard let url = URL(string: "\(baseStr)/s/\(encId)?q=flac") else { return nil }
            var req = URLRequest(url: url)
            req.setValue("bytes=0-41", forHTTPHeaderField: "Range")
            req.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (http.statusCode == 200 || http.statusCode == 206),
                  let streamPath = http.value(forHTTPHeaderField: "X-Relay-Stream"),
                  let resolved = URL(string: streamPath, relativeTo: server.url)?.absoluteURL,
                  resolved.host == server.url.host else {
                return nil
            }
            let total = parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range"))
            return (resolved, data, total)
        }
    }

    private func parseContentRangeTotal(_ header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        return Int64(header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }
}
