import Foundation
import MochyCore

/// JioSaavn AAC 320/160/96 kbps module ported from Mochy's `JioSaavnModule.kt`.
public actor JioSaavnModule: MochyStreamModule {
    public nonisolated let id = "jiosaavn"
    public nonisolated let displayName = "JioSaavn AAC"
    public nonisolated let supportsDownload = true

    private static let bitrateUpgradeRegex = try! NSRegularExpression(
        pattern: #"_(12|48|96|160|320)\.(mp4|m4a|aac|mp3)(?=[?#]|$)"#,
        options: [.caseInsensitive]
    )

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream? {
        let queryText = "\(TrackMatcher.core(track.title)) \(track.artist)"
        let encoded = queryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? queryText
        guard let searchURL = URL(
            string: "https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=android&p=1&n=10&q=\(encoded)"
        ) else {
            return nil
        }

        var req = URLRequest(url: searchURL)
        req.setValue("explicit_content=1", forHTTPHeaderField: "Cookie")
        req.timeoutInterval = 10

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return nil
        }

        struct SaavnHit {
            let encryptedURL: String
            let title: String
        }

        let candidates: [TrackCandidate<SaavnHit>] = results.compactMap { row in
            guard let title = row["title"] as? String,
                  let moreInfo = row["more_info"] as? [String: Any],
                  let encrypted = moreInfo["encrypted_media_url"] as? String else {
                return nil
            }
            let artistMap = (moreInfo["artistMap"] as? [String: Any])?["primary_artists"] as? [[String: Any]]
            let artist = artistMap?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let dur = (moreInfo["duration"] as? String).flatMap(Int.init) ?? (moreInfo["duration"] as? Int)
            return TrackCandidate(
                item: SaavnHit(encryptedURL: encrypted, title: title),
                title: title,
                artist: artist,
                durationSeconds: dur
            )
        }

        let query = TrackQuery(title: track.title, artist: track.artist, durationSeconds: track.durationSeconds)
        guard let match = TrackMatcher.bestMatch(query: query, candidates: candidates)?.candidate,
              var decryptedURLString = CryptoUtils.decryptJioSaavnMediaURL(match.encryptedURL) else {
            return nil
        }

        let targetBitrate = quality == .low ? "96" : (quality == .medium ? "160" : "320")
        let nsRange = NSRange(decryptedURLString.startIndex..<decryptedURLString.endIndex, in: decryptedURLString)
        decryptedURLString = Self.bitrateUpgradeRegex.stringByReplacingMatches(
            in: decryptedURLString,
            range: nsRange,
            withTemplate: "_\(targetBitrate).$2"
        )

        guard let streamURL = URL(string: decryptedURLString), ModuleUrlGuard.isAllowedPublicURL(streamURL) else {
            return nil
        }

        // Verify Range 0-1 responsiveness
        var probe = URLRequest(url: streamURL)
        probe.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let (_, probeResp) = try await session.data(for: probe)
        guard let probeHttp = probeResp as? HTTPURLResponse, (probeHttp.statusCode == 200 || probeHttp.statusCode == 206) else {
            return nil
        }

        let bps = Int(targetBitrate).map { $0 * 1000 } ?? 320_000
        return ModuleStream(
            url: streamURL,
            format: .progressive,
            codec: "AAC",
            sampleRate: 44_100,
            bitDepth: 16,
            bitrate: bps,
            sourceId: id,
            sourceLabel: displayName,
            qualityBadge: "AAC \(targetBitrate) kbps",
            isDRM: false
        )
    }
}
