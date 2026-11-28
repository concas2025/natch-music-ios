import Foundation

public struct PlayerJsBundle: Sendable, Equatable {
    public let code: String
    public let hash: String
    public let signatureTimestamp: Int?
}

public enum PlayerJsError: Error, LocalizedError {
    case hashExtractionFailed
    case playerJsDownloadFailed

    public var errorDescription: String? {
        switch self {
        case .hashExtractionFailed:
            return "Could not extract YouTube player.js hash from iframe_api."
        case .playerJsDownloadFailed:
            return "Failed to download YouTube base.js player script."
        }
    }
}

/// Downloads and caches YouTube's `base.js` player script for 6 hours.
public actor PlayerJsFetcher {
    private static let iframeApiURL = URL(string: "https://www.youtube.com/iframe_api")!
    private static let cacheTTLSeconds: TimeInterval = 6 * 60 * 60
    private static let hashRegex = try! NSRegularExpression(
        pattern: #"\\?/s\\?/player\\?/([a-zA-Z0-9_-]+)\\?/"#
    )
    private static let stsRegex = try! NSRegularExpression(
        pattern: #"(?:signatureTimestamp|sts):(\d{5})"#
    )

    private let session: URLSession
    private let cacheDirectory: URL
    private var memoryCache: (bundle: PlayerJsBundle, fetchedAt: Date)?

    public init(session: URLSession? = nil, cacheDirectory: URL? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 8
            cfg.timeoutIntervalForResource = 16
            self.session = URLSession(configuration: cfg)
        }
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = caches.appendingPathComponent("mochy_player_js", isDirectory: true)
        }
    }

    public func invalidateCache() {
        memoryCache = nil
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    public func getPlayerJs(forceRefresh: Bool = false) async throws -> PlayerJsBundle {
        if !forceRefresh, let cached = memoryCache,
           Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTLSeconds {
            return cached.bundle
        }

        if !forceRefresh, let diskCached = readDiskCache() {
            memoryCache = (diskCached, Date())
            return diskCached
        }

        let hash = try await fetchPlayerHash()
        guard let playerURL = URL(string: "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_GB/base.js") else {
            throw PlayerJsError.playerJsDownloadFailed
        }

        var request = URLRequest(url: playerURL)
        request.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let code = String(data: data, encoding: .utf8), code.count > 1_000 else {
            throw PlayerJsError.playerJsDownloadFailed
        }

        let sts = Self.extractSignatureTimestamp(from: code)
        let bundle = PlayerJsBundle(code: code, hash: hash, signatureTimestamp: sts)
        memoryCache = (bundle, Date())
        writeDiskCache(bundle)
        return bundle
    }

    public static func extractPlayerHash(from iframeApiScript: String) -> String? {
        let range = NSRange(iframeApiScript.startIndex..<iframeApiScript.endIndex, in: iframeApiScript)
        guard let match = hashRegex.firstMatch(in: iframeApiScript, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: iframeApiScript) else {
            return nil
        }
        return String(iframeApiScript[captureRange])
    }

    public static func extractSignatureTimestamp(from playerJs: String) -> Int? {
        let range = NSRange(playerJs.startIndex..<playerJs.endIndex, in: playerJs)
        guard let match = stsRegex.firstMatch(in: playerJs, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: playerJs) else {
            return nil
        }
        return Int(playerJs[captureRange])
    }

    private func fetchPlayerHash() async throws -> String {
        var request = URLRequest(url: Self.iframeApiURL)
        request.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = String(data: data, encoding: .utf8),
              let hash = Self.extractPlayerHash(from: body) else {
            throw PlayerJsError.hashExtractionFailed
        }
        return hash
    }

    private func readDiskCache() -> PlayerJsBundle? {
        let metaURL = cacheDirectory.appendingPathComponent("meta.json")
        let jsURL = cacheDirectory.appendingPathComponent("base.js")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: jsURL.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheTTLSeconds,
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(CacheMeta.self, from: metaData),
              let code = try? String(contentsOf: jsURL, encoding: .utf8),
              code.count > 1_000 else {
            return nil
        }
        return PlayerJsBundle(code: code, hash: meta.hash, signatureTimestamp: meta.signatureTimestamp)
    }

    private func writeDiskCache(_ bundle: PlayerJsBundle) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let metaData = try JSONEncoder().encode(
                CacheMeta(hash: bundle.hash, signatureTimestamp: bundle.signatureTimestamp)
            )
            try metaData.write(to: cacheDirectory.appendingPathComponent("meta.json"), options: .atomic)
            try bundle.code.write(
                to: cacheDirectory.appendingPathComponent("base.js"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Disk cache failure is non-fatal; memory cache remains active.
        }
    }

    private struct CacheMeta: Codable {
        let hash: String
        let signatureTimestamp: Int?
    }
}
