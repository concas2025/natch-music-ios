import Foundation
import JavaScriptCore
import MochyCore
#if os(iOS) && canImport(MusicKit)
import MusicKit
#endif

/// REST JSON WebModule supporting external module manifests up to 256 KB.
public actor WebStreamModule: MochyStreamModule {
    public struct Manifest: Codable, Sendable {
        public let id: String
        public let name: String
        public let supportsDownload: Bool?
    }

    public nonisolated let id: String
    public nonisolated let displayName: String
    public nonisolated let supportsDownload: Bool

    private let baseURL: URL
    private let session: URLSession

    public init(id: String, displayName: String, baseURL: URL, supportsDownload: Bool = true, session: URLSession = .shared) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.supportsDownload = supportsDownload
        self.session = session
    }

    public static func loadManifest(from baseURL: URL, session: URLSession = .shared) async throws -> Manifest? {
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        guard ModuleUrlGuard.isAllowedPublicURL(manifestURL) else { return nil }
        let (data, resp) = try await session.data(from: manifestURL)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= ModuleUrlGuard.maxManifestBytes else {
            return nil
        }
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        guard ModuleUrlGuard.isAllowedPublicURL(baseURL) else { return nil }
        let qParam = quality == .high ? "HI_RES_LOSSLESS" : (quality == .medium ? "HIGH" : "LOW")
        let encoded = "\(track.artist) \(TrackMatcher.core(track.title))"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.title
        guard let url = URL(string: "\(baseURL.absoluteString)/search?q=\(encoded)&quality=\(qParam)") else {
            return nil
        }

        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = root["tracks"] as? [[String: Any]] else {
            return nil
        }

        for row in tracks {
            guard let rawURL = row["streamURL"] as? String ?? row["streamUrl"] as? String,
                  let streamURL = URL(string: rawURL),
                  ModuleUrlGuard.isAllowedPublicURL(streamURL) else {
                continue
            }
            let rawFormat = (row["format"] as? String)?.lowercased() ?? "progressive"
            let format = StreamFormat(rawValue: rawFormat) ?? .progressive
            let codec = (row["codec"] as? String) ?? "AAC"
            let sampleRate = row["sampleRate"] as? Int
            let bitDepth = row["bitDepth"] as? Int
            let bitrate = row["bitrate"] as? Int
            let rawHeaders = (row["headers"] as? [String: String]) ?? [:]
            return ModuleStream(
                url: streamURL,
                headers: ModuleUrlGuard.sanitizeHeaders(rawHeaders),
                format: format,
                codec: codec,
                sampleRate: sampleRate,
                bitDepth: bitDepth,
                bitrate: bitrate,
                sourceId: id,
                sourceLabel: displayName,
                qualityBadge: "\(codec)\(sampleRate.map { " · \($0 / 1000)kHz" } ?? "")",
                isDRM: false
            )
        }
        return nil
    }
}

/// Apple-compliant sandboxed JS plugin module executed via `JavaScriptCore`.
public actor JSScriptModule: MochyStreamModule {
    public nonisolated let id: String
    public nonisolated let displayName: String
    public nonisolated let supportsDownload = false

    private let scriptSource: String

    public init(id: String, displayName: String, scriptSource: String) {
        self.id = id
        self.displayName = displayName
        self.scriptSource = scriptSource
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        guard let ctx = JSContext() else { return nil }
        ctx.evaluateScript(scriptSource)
        guard let fn = ctx.objectForKeyedSubscript("resolveTrack"), !fn.isUndefined else {
            return nil
        }
        let arg: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "artist": track.artist,
            "quality": quality.rawValue,
        ]
        guard let out = fn.call(withArguments: [arg])?.toDictionary(),
              let rawURL = out["url"] as? String,
              let url = URL(string: rawURL),
              ModuleUrlGuard.isAllowedPublicURL(url) else {
            return nil
        }
        return ModuleStream(
            url: url,
            codec: (out["codec"] as? String) ?? "AAC",
            bitrate: out["bitrate"] as? Int,
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: (out["badge"] as? String) ?? "JS Plugin"
        )
    }
}

/// Apple Music native iOS MusicKit catalog matcher (FairPlay DRM: bypasses custom Audio Engine DSP).
public actor AppleMusicModule: MochyStreamModule {
    public nonisolated let id = "applemusic"
    public nonisolated let displayName = "Apple Music (FairPlay)"
    public nonisolated let supportsDownload = false

    public init() {}

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        #if os(iOS) && canImport(MusicKit)
        guard MusicAuthorization.currentStatus == .authorized else { return nil }
        var request = MusicCatalogSearchRequest(
            term: "\(TrackMatcher.core(track.title)) \(track.artist)",
            types: [Song.self]
        )
        request.limit = 5
        let response = try await request.response()
        let candidates = response.songs.map {
            TrackCandidate(
                item: $0,
                title: $0.title,
                artist: $0.artistName,
                durationSeconds: $0.duration.map(Int.init),
                isrc: $0.isrc
            )
        }
        let query = TrackQuery(title: track.title, artist: track.artist, durationSeconds: track.durationSeconds, isrc: track.isrc)
        guard let song = TrackMatcher.bestMatch(query: query, candidates: candidates)?.candidate,
              let url = URL(string: "musickit://track/\(song.id.rawValue)") else {
            return nil
        }
        return ModuleStream(
            url: url,
            format: .hls,
            codec: "ALAC/AAC",
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: "Apple Music · FairPlay DRM",
            isDRM: true
        )
        #else
        return nil
        #endif
    }
}
