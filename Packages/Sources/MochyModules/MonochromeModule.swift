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
        // "fLaC" magic + metadata block type 0 (STREAMINFO, low 7 bits)
        guard bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else {
            return nil
        }
        guard (bytes[4] & 0x7F) == 0 else { return nil }

        // STREAMINFO starts at byte 8. Bytes 18..21 hold 20-bit sampleRate | 3-bit (channels-1) | 5-bit (bps-1)
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

/// Lossless FLAC / Hi-Res FLAC source module modeled after Mochy's `MonochromeModule.kt`.
public actor MonochromeModule: MochyStreamModule {
    public enum ServerKind: Sendable {
        case streamer
        case relay
    }

    public nonisolated let id = "monochrome"
    public nonisolated let displayName = "Monochrome FLAC"
    public nonisolated let supportsDownload = true

    public static let defaultBaseURL = URL(string: "https://tracks.monochrome.st")!
    private static let missMemorySeconds: TimeInterval = 30 * 60
    private static let unreachableRetrySeconds: TimeInterval = 10 * 60

    private let baseURL: URL
    private let serverKind: ServerKind
    private let session: URLSession
    private var missCache: [String: Date] = [:]
    private var unreachableUntil: Date = .distantPast

    public init(
        baseURL: URL = MonochromeModule.defaultBaseURL,
        serverKind: ServerKind = .streamer,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.serverKind = serverKind
        self.session = session
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        guard Date() >= unreachableUntil else { return nil }
        if let missedAt = missCache[track.id], Date().timeIntervalSince(missedAt) < Self.missMemorySeconds {
            return nil
        }

        let queryText = "\(track.artist) \(TrackMatcher.core(track.title))"
        guard let matchedId = try await searchBestTrackId(track: track, queryText: queryText) else {
            missCache[track.id] = Date()
            return nil
        }

        guard let streamURL = try await resolveStreamURL(matchedId: matchedId) else {
            missCache[track.id] = Date()
            return nil
        }

        guard ModuleUrlGuard.isAllowedPublicURL(streamURL),
              let info = try await probeFlacHeader(url: streamURL) else {
            missCache[track.id] = Date()
            return nil
        }

        // CoreAudio supports up to 192 kHz 24-bit natively.
        guard info.sampleRate <= 192_000 else {
            return nil
        }

        return ModuleStream(
            url: streamURL,
            headers: [:],
            format: .progressive,
            codec: "FLAC",
            sampleRate: info.sampleRate,
            bitDepth: info.bitsPerSample,
            bitrate: info.sampleRate * info.channels * info.bitsPerSample,
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: info.qualityBadge,
            isDRM: false
        )
    }

    private func searchBestTrackId(track: ModuleTrack, queryText: String) async throws -> String? {
        let encoded = queryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? queryText
        let urlString: String
        switch serverKind {
        case .streamer:
            urlString = "\(baseURL.absoluteString)/search/tracks?q=\(encoded)&limit=8"
        case .relay:
            urlString = "\(baseURL.absoluteString)/search?q=\(encoded)&n=8"
        }
        guard let url = URL(string: urlString), ModuleUrlGuard.isAllowedPublicURL(url) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if serverKind == .relay {
            req.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            unreachableUntil = Date().addingTimeInterval(Self.unreachableRetrySeconds)
            throw error
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let listKey = serverKind == .streamer ? "tracks" : "data"
        guard let items = json[listKey] as? [[String: Any]] else { return nil }

        let candidates: [TrackCandidate<String>] = items.compactMap { row in
            let itemId: String?
            if let str = row["id"] as? String { itemId = str }
            else if let num = row["id"] as? Int { itemId = String(num) }
            else { itemId = nil }
            guard let id = itemId, let title = row["title"] as? String else { return nil }
            let artist = (row["artist"] as? String) ?? (row["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let durSec = (row["duration"] as? Int) ?? (row["durationMs"] as? Int).map { $0 / 1000 }
            let isrc = row["isrc"] as? String
            return TrackCandidate(item: id, title: title, artist: artist, durationSeconds: durSec, isrc: isrc)
        }

        let query = TrackQuery(
            title: track.title,
            artist: track.artist,
            durationSeconds: track.durationSeconds,
            isrc: track.isrc
        )
        return TrackMatcher.bestMatch(query: query, candidates: candidates)?.candidate
    }

    private func resolveStreamURL(matchedId: String) async throws -> URL? {
        switch serverKind {
        case .streamer:
            return URL(string: "\(baseURL.absoluteString)/track/\(matchedId)")
        case .relay:
            guard let url = URL(string: "\(baseURL.absoluteString)/s/\(matchedId)?q=flac") else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            req.setValue("relay/2", forHTTPHeaderField: "X-Relay-Client")
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  let streamPath = http.value(forHTTPHeaderField: "X-Relay-Stream"),
                  let resolved = URL(string: streamPath, relativeTo: baseURL)?.absoluteURL,
                  resolved.host == baseURL.host else {
                return nil
            }
            return resolved
        }
    }

    private func probeFlacHeader(url: URL) async throws -> FlacStreamInfo? {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-41", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206) else {
            return nil
        }
        return FlacStreamInfoParser.parse(data)
    }
}
