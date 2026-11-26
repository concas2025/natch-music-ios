import Foundation

/// 512 KB HTTP Range chunked LRU disk cache modeled after Mochy's chunked stream cache (`CHUNK_LENGTH = 512 * 1024`).
public actor ChunkRangeCache {
    public static let chunkLengthBytes = 512 * 1024

    private struct IndexMeta: Codable {
        var maxBytes: Int64
        var completedMediaIds: Set<String>
        var lastAccess: [String: TimeInterval]
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
           let decoded = try? JSONDecoder().decode(IndexMeta.self, from: data) {
            self.meta = decoded
        } else {
            self.meta = IndexMeta(maxBytes: maxCacheBytes, completedMediaIds: [], lastAccess: [:])
        }
    }

    public func isFullyCached(mediaId: String) -> Bool {
        meta.completedMediaIds.contains(mediaId) && FileManager.default.fileExists(atPath: completeFileURL(mediaId: mediaId).path)
    }

    public func completeFileURL(mediaId: String) -> URL {
        directory.appendingPathComponent("\(safeId(mediaId)).audio")
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

    public func markCompleted(mediaId: String, fullFileData: Data) throws {
        try fullFileData.write(to: completeFileURL(mediaId: mediaId), options: .atomic)
        meta.completedMediaIds.insert(mediaId)
        meta.lastAccess[mediaId] = Date().timeIntervalSince1970
        evictIfNeeded()
        saveMeta()
    }

    /// Prefetches the opening 512 KB chunk for instant SkipBlend / Crossmix start.
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
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
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
}
