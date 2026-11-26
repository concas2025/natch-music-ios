import Foundation
import MochyCore

/// JioSaavn AAC 320/160/96 kbps module matching `realidkroo/Mochy-Music`'s `JioSaavnModule.kt`:
/// HTML-entity unescaping, `320kbps` flag detection with safe fallback to original URL, and miss/outage caches.
public actor JioSaavnModule: MochyStreamModule {
    public nonisolated let id = "jiosaavn"
    public nonisolated let displayName = "JioSaavn AAC"
    public nonisolated let supportsDownload = true

    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    private static let missMemorySeconds: TimeInterval = 30 * 60
    private static let unreachableRetrySeconds: TimeInterval = 10 * 60
    private static let bitrateUpgradeRegex = try! NSRegularExpression(
        pattern: #"_(12|48|96|160|320)\.(mp4|m4a|aac|mp3)(?=[?#]|$)"#,
        options: [.caseInsensitive]
    )

    public struct SaavnHit: Sendable, Equatable {
        public let encryptedURL: String
        public let title: String
        public let artist: String
        public let durationSeconds: Int?
        public let has320: Bool
    }

    private let session: URLSession
    private var matchCache: [String: SaavnHit] = [:]
    private var missCache: [String: Date] = [:]
    private var unreachableUntil: Date = .distantPast

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 8
            cfg.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: cfg)
        }
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        guard Date() >= unreachableUntil else { return nil }
        let cacheKey = "\(track.title)|\(track.artist)"
        if let missedAt = missCache[cacheKey], Date().timeIntervalSince(missedAt) < Self.missMemorySeconds {
            return nil
        }

        let match: SaavnHit
        if let cached = matchCache[cacheKey] {
            match = cached
        } else {
            let primaryArtist = track.artist.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? track.artist
            let queryText = "\(TrackMatcher.core(track.title)) \(primaryArtist)".trimmingCharacters(in: .whitespaces)
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            let encoded = queryText.addingPercentEncoding(withAllowedCharacters: allowed) ?? queryText
            guard let searchURL = URL(
                string: "https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=android&p=1&n=10&q=\(encoded)"
            ) else {
                return nil
            }

            var req = URLRequest(url: searchURL)
            req.setValue("explicit_content=1", forHTTPHeaderField: "Cookie")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: req)
            } catch {
                unreachableUntil = Date().addingTimeInterval(Self.unreachableRetrySeconds)
                return nil
            }

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let candidates = Self.parseSearchCandidates(from: json)
            let query = TrackQuery(title: track.title, artist: track.artist, durationSeconds: track.durationSeconds)
            guard let best = TrackMatcher.bestMatch(query: query, candidates: candidates)?.candidate else {
                missCache[cacheKey] = Date()
                return nil
            }
            matchCache[cacheKey] = best
            match = best
        }

        guard let givenURLString = CryptoUtils.decryptJioSaavnMediaURL(match.encryptedURL),
              givenURLString.hasPrefix("http") else {
            return nil
        }

        let wantedKbps: Int
        switch quality {
        case .low: wantedKbps = 96
        case .medium: wantedKbps = 160
        case .high, .auto: wantedKbps = match.has320 ? 320 : 160
        }

        let resolved = await resolveBestRendition(givenURLString: givenURLString, wantedKbps: wantedKbps)
        guard let streamURL = URL(string: resolved.urlString),
              ModuleUrlGuard.isAllowedPublicURL(streamURL) else {
            return nil
        }

        return ModuleStream(
            url: streamURL,
            headers: ["User-Agent": Self.userAgent],
            format: .progressive,
            codec: "AAC",
            mimeType: "audio/mp4",
            contentLength: resolved.contentLength,
            durationSeconds: match.durationSeconds ?? track.durationSeconds,
            sampleRate: 44_100,
            bitDepth: 16,
            bitrate: resolved.kbps * 1000,
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: "AAC \(resolved.kbps) kbps",
            isDRM: false
        )
    }

    public static func parseSearchCandidates(from json: [String: Any]) -> [TrackCandidate<SaavnHit>] {
        guard let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { row in
            guard let rawTitle = row["title"] as? String,
                  let moreInfo = row["more_info"] as? [String: Any],
                  let encrypted = moreInfo["encrypted_media_url"] as? String, !encrypted.isEmpty else {
                return nil
            }
            let title = unescapeHTML(rawTitle)
            let artistMap = (moreInfo["artistMap"] as? [String: Any])?["primary_artists"] as? [[String: Any]]
            let artist = artistMap?.compactMap { ($0["name"] as? String).map(unescapeHTML) }.joined(separator: ", ") ?? ""
            let dur = (moreInfo["duration"] as? String).flatMap(Int.init) ?? (moreInfo["duration"] as? Int)
            let has320 = (moreInfo["320kbps"] as? String)?.lowercased() == "true" || (moreInfo["320kbps"] as? Bool) == true
            let hit = SaavnHit(
                encryptedURL: encrypted,
                title: title,
                artist: artist,
                durationSeconds: dur,
                has320: has320
            )
            return TrackCandidate(
                item: hit,
                title: title,
                artist: artist,
                durationSeconds: dur
            )
        }
    }

    public static func unescapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveBestRendition(givenURLString: String, wantedKbps: Int) async -> (urlString: String, kbps: Int, contentLength: Int64?) {
        let nsRange = NSRange(givenURLString.startIndex..<givenURLString.endIndex, in: givenURLString)
        guard let match = Self.bitrateUpgradeRegex.firstMatch(in: givenURLString, range: nsRange),
              let rateRange = Range(match.range(at: 1), in: givenURLString),
              let offeredKbps = Int(givenURLString[rateRange]) else {
            let probe = await probeRange(givenURLString)
            return (givenURLString, wantedKbps, probe.contentLength)
        }

        if offeredKbps == wantedKbps {
            let probe = await probeRange(givenURLString)
            return (givenURLString, offeredKbps, probe.contentLength)
        }

        let upgraded = Self.bitrateUpgradeRegex.stringByReplacingMatches(
            in: givenURLString,
            range: nsRange,
            withTemplate: "_\(wantedKbps).$2"
        )
        let upgradedProbe = await probeRange(upgraded)
        if upgradedProbe.ok {
            return (upgraded, wantedKbps, upgradedProbe.contentLength)
        }

        // Fallback safely to original offered rendition instead of failing the entire track!
        let fallbackProbe = await probeRange(givenURLString)
        return (givenURLString, offeredKbps, fallbackProbe.contentLength)
    }

    private func probeRange(_ urlString: String) async -> (ok: Bool, contentLength: Int64?) {
        guard let url = URL(string: urlString) else { return (false, nil) }
        var probe = URLRequest(url: url)
        probe.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        probe.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await session.data(for: probe),
              let http = resp as? HTTPURLResponse,
              (http.statusCode == 200 || http.statusCode == 206) else {
            return (false, nil)
        }
        var total: Int64?
        if let cr = http.value(forHTTPHeaderField: "Content-Range"), let slash = cr.lastIndex(of: "/") {
            total = Int64(cr[cr.index(after: slash)...].trimmingCharacters(in: .whitespaces))
        }
        return (true, total)
    }
}
