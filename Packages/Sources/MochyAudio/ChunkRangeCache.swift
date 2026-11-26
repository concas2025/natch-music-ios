import Foundation

/// HTTP Range chunked LRU disk cache with real container file extensions (`.m4a`, `.flac`, `.mp3`, `.mp4`)
/// so CoreAudio / `AVURLAsset` opens completed cached files without `kAudioFileUnsupportedFileTypeError`.
public actor ChunkRangeCache {
    public static let chunkLengthBytes = 256 * 1024

    private struct IndexMeta: Codable {
        var maxBytes: Int64
        var completedMediaIds: Set<String>
        var lastAccess: [String: TimeInterval]
        var fileExtensions: [String: String]?
    }

    private let directory: URL
    private let maxCacheBytes: Int64
    private var meta: IndexMeta

    public init(directory: URL? = nil, maxCacheBytes: Int64 = 512 * 1024 * 1024) {
        let base = directory ?? (
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        ).appendingPathComponent("mochy_audio_chunks", isDirectory: true)
        self.directory = base
        self.maxCacheBytes = maxCacheBytes
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let metaURL = base.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: metaURL),
           var decoded = try? JSONDecoder().decode(IndexMeta.self, from: data) {
            if decoded.fileExtensions == nil { decoded.fileExtensions = [:] }
            self.meta = decoded
        } else {
            self.meta = IndexMeta(maxBytes: maxCacheBytes, completedMediaIds: [], lastAccess: [:], fileExtensions: [:])
        }
    }

    public func isFullyCached(mediaId: String) -> Bool {
        meta.completedMediaIds.contains(mediaId) && FileManager.default.fileExists(atPath: completeFileURL(mediaId: mediaId).path)
    }

    public func completeFileURL(mediaId: String, fileExtension: String? = nil) -> URL {
        let ext = Self.sanitizedExtension(fileExtension ?? meta.fileExtensions?[mediaId] ?? "m4a")
        return directory.appendingPathComponent("\(safeId(mediaId)).\(ext)")
    }

    public func downloadedMediaIds() -> Set<String> {
        meta.completedMediaIds.filter { id in
            FileManager.default.fileExists(atPath: completeFileURL(mediaId: id).path)
        }
    }

    public func totalDiskUsageBytes() -> Int64 {
        currentDiskUsageBytes()
    }

    public func storeChunk(mediaId: String, chunkIndex: Int, data: Data) throws {
        let mediaDir = directory.appendingPathComponent(safeId(mediaId), isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let chunkURL = mediaDir.appendingPathComponent("\(chunkIndex).chk")
        try data.write(to: chunkURL, options: .atomic)
        meta.lastAccess[mediaId] = Date().timeIntervalSince1970
        evictIfNeeded()
        saveMeta()
    }

    public func readChunk(mediaId: String, chunkIndex: Int) -> Data? {
        let chunkURL = directory.appendingPathComponent(safeId(mediaId), isDirectory: true)
            .appendingPathComponent("\(chunkIndex).chk")
        guard let data = try? Data(contentsOf: chunkURL) else { return nil }
        meta.lastAccess[mediaId] = Date().timeIntervalSince1970
        saveMeta()
        return data
    }

    public func markCompleted(mediaId: String, fileExtension: String = "m4a", fullFileData: Data) throws {
        let ext = Self.sanitizedExtension(fileExtension)
        var exts = meta.fileExtensions ?? [:]
        exts[mediaId] = ext
        meta.fileExtensions = exts
        let target = completeFileURL(mediaId: mediaId, fileExtension: ext)
        try fullFileData.write(to: target, options: .atomic)
        meta.completedMediaIds.insert(mediaId)
        meta.lastAccess[mediaId] = Date().timeIntervalSince1970
        evictIfNeeded()
        saveMeta()
    }

    /// Promotes a completed file from `LocalAudioProxy`'s sparse buffer directly into the LRU cache.
    public func copyCompletedFile(mediaId: String, from sourceURL: URL, fileExtension: String) throws -> URL {
        let ext = Self.sanitizedExtension(fileExtension)
        var exts = meta.fileExtensions ?? [:]
        exts[mediaId] = ext
        meta.fileExtensions = exts
        let target = completeFileURL(mediaId: mediaId, fileExtension: ext)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: sourceURL, to: target)
        meta.completedMediaIds.insert(mediaId)
        meta.lastAccess[mediaId] = Date().timeIntervalSince1970
        evictIfNeeded()
        saveMeta()
        return target
    }

    public func removeMedia(mediaId: String) {
        let chunkDir = directory.appendingPathComponent(safeId(mediaId), isDirectory: true)
        let fullFile = completeFileURL(mediaId: mediaId)
        try? FileManager.default.removeItem(at: chunkDir)
        try? FileManager.default.removeItem(at: fullFile)
        meta.completedMediaIds.remove(mediaId)
        meta.lastAccess.removeValue(forKey: mediaId)
        meta.fileExtensions?.removeValue(forKey: mediaId)
        saveMeta()
    }

    public func clearAll() {
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in contents {
                try? FileManager.default.removeItem(at: item)
            }
        }
        meta = IndexMeta(maxBytes: maxCacheBytes, completedMediaIds: [], lastAccess: [:], fileExtensions: [:])
        saveMeta()
    }

    public func prefetchFirstChunk(
        mediaId: String,
        url: URL,
        headers: [String: String],
        session: URLSession = .shared
    ) async {
        if readChunk(mediaId: mediaId, chunkIndex: 0) != nil || isFullyCached(mediaId: mediaId) {
            return
        }
        var req = URLRequest(url: url)
        req.setValue("bytes=0-\(Self.chunkLengthBytes - 1)", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (http.statusCode == 200 || http.statusCode == 206),
              !data.isEmpty else {
            return
        }
        try? storeChunk(mediaId: mediaId, chunkIndex: 0, data: data)
    }

    private func evictIfNeeded() {
        var total = currentDiskUsageBytes()
        guard total > maxCacheBytes else { return }
        let sortedOldest = meta.lastAccess.sorted { $0.value < $1.value }.map(\.key)
        for id in sortedOldest {
            guard total > maxCacheBytes else { break }
            let chunkDir = directory.appendingPathComponent(safeId(id), isDirectory: true)
            let fullFile = completeFileURL(mediaId: id)
            try? FileManager.default.removeItem(at: chunkDir)
            try? FileManager.default.removeItem(at: fullFile)
            meta.completedMediaIds.remove(id)
            meta.lastAccess.removeValue(forKey: id)
            meta.fileExtensions?.removeValue(forKey: id)
            total = currentDiskUsageBytes()
        }
    }

    private func currentDiskUsageBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        var sum: Int64 = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent != "index.json" else { continue }
            if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true,
               let size = vals.fileSize {
                sum += Int64(size)
            }
        }
        return sum
    }

    private func saveMeta() {
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        }
    }

    private func safeId(_ id: String) -> String {
        id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    }

    public static func sanitizedExtension(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
        switch lower {
        case "m4a", "mp4", "flac", "mp3", "wav", "aac", "alac", "caf":
            return lower
        default:
            return "m4a"
        }
    }
}
