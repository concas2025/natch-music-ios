import Foundation
import Network
import os

private final class OnceContinuation<T: Sendable>: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        os_unfair_lock_lock(&lock)
        let cont = continuation
        continuation = nil
        os_unfair_lock_unlock(&lock)
        cont?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        os_unfair_lock_lock(&lock)
        let cont = continuation
        continuation = nil
        os_unfair_lock_unlock(&lock)
        cont?.resume(throwing: error)
    }
}

public struct ProxyStreamDescriptor: Sendable, Equatable {
    public let trackId: String
    public let url: URL
    public let headers: [String: String]
    public let mimeType: String
    public let contentLength: Int64?

    public init(
        trackId: String,
        url: URL,
        headers: [String: String] = [:],
        mimeType: String = "audio/mp4",
        contentLength: Int64? = nil
    ) {
        self.trackId = trackId
        self.url = url
        self.headers = headers
        self.mimeType = mimeType
        self.contentLength = contentLength
    }

    public var fileExtension: String {
        let lower = mimeType.lowercased()
        if lower.contains("flac") { return "flac" }
        if lower.contains("mpeg") || lower.contains("mp3") { return "mp3" }
        if lower.contains("wav") { return "wav" }
        if lower.contains("video/mp4") { return "mp4" }
        if lower.contains("audio/mp4") || lower.contains("mp4a") || lower.contains("aac") { return "m4a" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "m4a" : ChunkRangeCache.sanitizedExtension(ext)
    }

    public var isMp4Container: Bool {
        let lower = mimeType.lowercased()
        return lower.contains("mp4") || lower.contains("m4a") || fileExtension == "m4a" || fileExtension == "mp4"
    }
}

public enum LocalAudioProxyError: Error, LocalizedError {
    case failedToBindListener(String)
    case couldNotDetermineContentLength

    public var errorDescription: String? {
        switch self {
        case let .failedToBindListener(reason):
            return "LocalAudioProxy could not bind loopback listener: \(reason)"
        case .couldNotDetermineContentLength:
            return "Upstream audio stream did not report total Content-Length."
        }
    }
}

/// Battle-tested native iOS loopback HTTP/1.1 Range proxy (`127.0.0.1:<ephemeral>`) modeled after
/// Lemielmusic's `local_audio_proxy_io.dart`:
/// - Pre-allocates sparse disk buffer per track with proper container extension (`.m4a`/`.flac`/`.mp3`)
/// - 256 KB chunk bitmap + concurrent in-flight task coalescing + sequential background prefetcher
/// - In-place zero-byte-shift ISO BMFF `moov/mvex` duration normalization on Chunk 0 (eliminates AVPlayer 2x duration bug)
/// - Strict exact-byte validation + mid-stream `403`/`410` URL hot-swap + YouTube `mn=` CDN cluster failover
/// - Aborts TCP connection (`forceCancel`) on premature upstream drop instead of sending corrupted zeroes
public actor LocalAudioProxy {
    public typealias StreamRefreshHandler = @Sendable (_ trackId: String) async -> ProxyStreamDescriptor?

    public static let chunkSize = 256 * 1024

    private let cache: ChunkRangeCache
    private let session: URLSession
    private let tempDirectory: URL
    private let networkQueue = DispatchQueue(label: "com.natch.music.localproxy", qos: .userInitiated)

    private var listener: NWListener?
    private var boundPort: UInt16?
    private var sessionsByToken: [String: DiskStreamSession] = [:]
    private var tokenByTrackId: [String: String] = [:]

    public init(
        cache: ChunkRangeCache = ChunkRangeCache(),
        session: URLSession? = nil,
        tempDirectory: URL? = nil
    ) {
        self.cache = cache
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 60
            cfg.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: cfg)
        }
        self.tempDirectory = tempDirectory ?? (
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        ).appendingPathComponent("natch_proxy_buffers", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true)
    }

    public func ensureStarted() async throws -> UInt16 {
        if let boundPort, listener != nil {
            return boundPort
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)

        let newListener = try NWListener(using: params)
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OnceContinuation(cont)
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let rawPort = newListener.port?.rawValue {
                        once.resume(returning: rawPort)
                    } else {
                        once.resume(throwing: LocalAudioProxyError.failedToBindListener("No port assigned"))
                    }
                case let .failed(error):
                    once.resume(throwing: LocalAudioProxyError.failedToBindListener(error.localizedDescription))
                case .cancelled:
                    once.resume(throwing: LocalAudioProxyError.failedToBindListener("Listener cancelled"))
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handleConnection(connection) }
            }
            newListener.start(queue: networkQueue)
        }

        newListener.stateUpdateHandler = nil
        self.listener = newListener
        self.boundPort = port
        return port
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        boundPort = nil
        for sess in sessionsByToken.values {
            await sess.cancelPrefetch()
        }
        sessionsByToken.removeAll()
        tokenByTrackId.removeAll()
    }

    /// Registers an upstream HTTP/HTTPS stream and returns its local `http://127.0.0.1:<port>/stream/<token>.<ext>` URL.
    public func registerStream(
        _ descriptor: ProxyStreamDescriptor,
        onRefresh: StreamRefreshHandler? = nil
    ) async throws -> URL {
        let port = try await ensureStarted()

        if let existingToken = tokenByTrackId[descriptor.trackId],
           let existing = sessionsByToken[existingToken] {
            await existing.updateDescriptor(descriptor, onRefresh: onRefresh)
            await existing.startPrefetchIfNeeded()
            return URL(string: "http://127.0.0.1:\(port)/stream/\(existingToken).\(descriptor.fileExtension)")!
        }

        let totalBytes: Int64
        if let knownLen = descriptor.contentLength, knownLen > 0 {
            totalBytes = knownLen
        } else {
            totalBytes = try await probeContentLength(for: descriptor)
        }

        // Evict stale buffers if more than 8 sessions are live in temp storage.
        if sessionsByToken.count >= 8 {
            await evictOldestSession()
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let fileURL = tempDirectory.appendingPathComponent("\(token).\(descriptor.fileExtension)")
        let diskSession = try DiskStreamSession(
            token: token,
            descriptor: descriptor,
            totalBytes: totalBytes,
            fileURL: fileURL,
            session: session,
            cache: cache,
            onRefresh: onRefresh
        )
        sessionsByToken[token] = diskSession
        tokenByTrackId[descriptor.trackId] = token
        await diskSession.startPrefetchIfNeeded()

        return URL(string: "http://127.0.0.1:\(port)/stream/\(token).\(descriptor.fileExtension)")!
    }

    /// Returns a completed on-disk file URL if the track has finished downloading in the proxy or persistent cache.
    public func completedFileURL(forTrackId trackId: String) async -> URL? {
        if await cache.isFullyCached(mediaId: trackId) {
            return await cache.completeFileURL(mediaId: trackId)
        }
        if let token = tokenByTrackId[trackId],
           let sess = sessionsByToken[token] {
            return await sess.completedFileURLIfReady()
        }
        return nil
    }

    /// Extracts YouTube `mn=primary,fallback` failover host URLs when a `googlevideo.com` CDN node stalls.
    public static func buildFailoverURLs(for original: URL) -> [URL] {
        guard let host = original.host?.lowercased(), host.contains("googlevideo.com"),
              var comps = URLComponents(url: original, resolvingAgainstBaseURL: false),
              let mn = comps.queryItems?.first(where: { $0.name == "mn" })?.value else {
            return []
        }
        let nodes = mn.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard nodes.count >= 2 else { return [] }
        let fallbackNode = nodes[1]
        var urls: [URL] = []
        for prefix in ["rr1---", "rr2---"] {
            comps.host = "\(prefix)\(fallbackNode).googlevideo.com"
            if let alt = comps.url, alt != original {
                urls.append(alt)
            }
        }
        return urls
    }

    private func probeContentLength(for descriptor: ProxyStreamDescriptor) async throws -> Int64 {
        var req = URLRequest(url: descriptor.url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (k, v) in descriptor.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LocalAudioProxyError.couldNotDetermineContentLength
        }
        if let rangeHeader = http.value(forHTTPHeaderField: "Content-Range"),
           let slashIdx = rangeHeader.lastIndex(of: "/"),
           let parsedTotal = Int64(rangeHeader[rangeHeader.index(after: slashIdx)...].trimmingCharacters(in: .whitespaces)),
           parsedTotal > 0 {
            return parsedTotal
        }
        if http.expectedContentLength > 0 {
            return http.expectedContentLength
        }
        throw LocalAudioProxyError.couldNotDetermineContentLength
    }

    private func evictOldestSession() async {
        var oldestToken: String?
        var oldestTime = Date.distantFuture
        for (tok, sess) in sessionsByToken {
            let t = await sess.lastAccessedAt
            if t < oldestTime {
                oldestTime = t
                oldestToken = tok
            }
        }
        if let oldestToken, let removed = sessionsByToken.removeValue(forKey: oldestToken) {
            let tid = await removed.trackId
            if tokenByTrackId[tid] == oldestToken {
                tokenByTrackId.removeValue(forKey: tid)
            }
            await removed.dispose()
        }
    }

    // MARK: - HTTP/1.1 Loopback Connection Handler

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: networkQueue)
        Task { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            await self.serveHTTPRequest(on: connection)
        }
    }

    private func serveHTTPRequest(on connection: NWConnection) async {
        guard let rawRequest = await Self.readHTTPHeader(from: connection),
              let headerString = String(data: rawRequest, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            await Self.sendRaw(Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8), on: connection)
            connection.cancel()
            return
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        guard method == "GET" || method == "HEAD",
              path.hasPrefix("/stream/") else {
            await Self.sendRaw(Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8), on: connection)
            connection.cancel()
            return
        }

        let filePart = String(path.dropFirst("/stream/".count))
            .split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let token = filePart.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""

        guard let diskSession = sessionsByToken[token] else {
            await Self.sendRaw(Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8), on: connection)
            connection.cancel()
            return
        }

        var rangeHeader: String?
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "range" {
                    rangeHeader = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        let totalBytes = await diskSession.totalBytes
        let contentType = await diskSession.mimeType

        if method == "HEAD" {
            let headResp = """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Accept-Ranges: bytes\r
            Content-Length: \(totalBytes)\r
            Connection: close\r
            \r
            """
            await Self.sendRaw(Data(headResp.utf8), on: connection)
            connection.cancel()
            return
        }

        let (rangeStart, rangeEnd, isPartial): (Int64, Int64, Bool)
        if let rangeHeader, let parsed = Self.parseByteRange(rangeHeader, totalBytes: totalBytes) {
            rangeStart = parsed.start
            rangeEnd = parsed.end
            isPartial = true
        } else if rangeHeader != nil {
            let err416 = """
            HTTP/1.1 416 Range Not Satisfiable\r
            Content-Range: bytes */\(totalBytes)\r
            Connection: close\r
            \r
            """
            await Self.sendRaw(Data(err416.utf8), on: connection)
            connection.cancel()
            return
        } else {
            rangeStart = 0
            rangeEnd = max(0, totalBytes - 1)
            isPartial = false
        }

        // CoreMedia safety: fetch the first chunk BEFORE writing HTTP 200/206 status headers!
        let firstChunkIdx = Int(rangeStart / Int64(Self.chunkSize))
        let firstOk = await diskSession.ensureChunk(index: firstChunkIdx)
        guard firstOk else {
            let err502 = "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n"
            await Self.sendRaw(Data(err502.utf8), on: connection)
            connection.cancel()
            return
        }

        let responseLen = rangeEnd - rangeStart + 1
        let statusLine = isPartial ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 200 OK"
        var headerText = "\(statusLine)\r\n"
        headerText += "Content-Type: \(contentType)\r\n"
        headerText += "Accept-Ranges: bytes\r\n"
        headerText += "Content-Length: \(responseLen)\r\n"
        if isPartial {
            headerText += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalBytes)\r\n"
        }
        headerText += "Connection: close\r\n\r\n"

        guard await Self.sendRaw(Data(headerText.utf8), on: connection) else {
            connection.forceCancel()
            return
        }

        var cursor = rangeStart
        while cursor <= rangeEnd {
            let chunkIdx = Int(cursor / Int64(Self.chunkSize))
            let ok = await diskSession.ensureChunk(index: chunkIdx)
            guard ok else {
                // Upstream dropped mid-stream after headers were sent -> TCP RST so AVPlayer retries cleanly.
                connection.forceCancel()
                return
            }

            let chunkEndOffset = min(rangeEnd, Int64(chunkIdx + 1) * Int64(Self.chunkSize) - 1)
            let readLen = Int(chunkEndOffset - cursor + 1)
            guard let slice = await diskSession.readSlice(offset: cursor, length: readLen),
                  slice.count == readLen else {
                connection.forceCancel()
                return
            }

            guard await Self.sendRaw(slice, on: connection) else {
                connection.forceCancel()
                return
            }
            cursor += Int64(readLen)
        }

        connection.cancel()
    }

    private static func parseByteRange(_ header: String, totalBytes: Int64) -> (start: Int64, end: Int64)? {
        guard totalBytes > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("bytes=") else { return nil }
        let spec = String(trimmed.dropFirst("bytes=".count)).split(separator: ",").first.map(String.init) ?? ""
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard bounds.count == 2 else { return nil }

        if bounds[0].isEmpty, let suffix = Int64(bounds[1]), suffix > 0 {
            let start = max(0, totalBytes - suffix)
            return (start, totalBytes - 1)
        }
        guard let start = Int64(bounds[0]), start >= 0, start < totalBytes else { return nil }
        let end: Int64
        if bounds[1].isEmpty {
            end = totalBytes - 1
        } else if let parsedEnd = Int64(bounds[1]) {
            end = min(parsedEnd, totalBytes - 1)
        } else {
            return nil
        }
        guard start <= end else { return nil }
        return (start, end)
    }

    private static func readHTTPHeader(from connection: NWConnection) async -> Data? {
        var accumulated = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        while accumulated.count < 16_384 {
            let chunk: Data? = await withCheckedContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if error != nil {
                        cont.resume(returning: nil)
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else if isComplete {
                        cont.resume(returning: Data())
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            guard let chunk else { return nil }
            if chunk.isEmpty { break }
            accumulated.append(chunk)
            if accumulated.range(of: delimiter) != nil {
                return accumulated
            }
        }
        return accumulated.isEmpty ? nil : accumulated
    }

    @discardableResult
    private static func sendRaw(_ data: Data, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { cont in
            connection.send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: error == nil)
            })
        }
    }
}

// MARK: - Per-Track Sparse Disk Stream Buffer

private actor DiskStreamSession {
    let token: String
    let totalBytes: Int64
    let fileURL: URL

    private var descriptor: ProxyStreamDescriptor
    private var onRefresh: LocalAudioProxy.StreamRefreshHandler?
    private let session: URLSession
    private let cache: ChunkRangeCache

    private let chunkCount: Int
    private var downloadedChunks: [Bool]
    private var inFlight: [Int: Task<Bool, Never>] = [:]
    private var fileHandle: FileHandle?
    private var prefetchTask: Task<Void, Never>?
    private var promotedToPersistentCache = false
    private(set) var lastAccessedAt = Date()

    var trackId: String { descriptor.trackId }
    var mimeType: String { descriptor.mimeType }

    init(
        token: String,
        descriptor: ProxyStreamDescriptor,
        totalBytes: Int64,
        fileURL: URL,
        session: URLSession,
        cache: ChunkRangeCache,
        onRefresh: LocalAudioProxy.StreamRefreshHandler?
    ) throws {
        self.token = token
        self.descriptor = descriptor
        self.totalBytes = totalBytes
        self.fileURL = fileURL
        self.session = session
        self.cache = cache
        self.onRefresh = onRefresh

        let size = Int64(LocalAudioProxy.chunkSize)
        self.chunkCount = max(1, Int((totalBytes + size - 1) / size))
        self.downloadedChunks = Array(repeating: false, count: self.chunkCount)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forUpdating: fileURL)
        try handle.truncate(atOffset: UInt64(totalBytes))
        self.fileHandle = handle
    }

    func updateDescriptor(_ fresh: ProxyStreamDescriptor, onRefresh: LocalAudioProxy.StreamRefreshHandler?) {
        self.descriptor = fresh
        if let onRefresh { self.onRefresh = onRefresh }
        self.lastAccessedAt = Date()
    }

    func startPrefetchIfNeeded() {
        guard prefetchTask == nil else { return }
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            let count = self.chunkCount
            for idx in 0..<count {
                if Task.isCancelled { return }
                let ok = await self.ensureChunk(index: idx)
                if !ok {
                    // Pause prefetch on network drop; active range reads can still retry on demand.
                    return
                }
            }
        }
    }

    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func completedFileURLIfReady() -> URL? {
        downloadedChunks.allSatisfy { $0 } ? fileURL : nil
    }

    func dispose() {
        cancelPrefetch()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    func ensureChunk(index: Int) async -> Bool {
        guard index >= 0, index < chunkCount else { return false }
        lastAccessedAt = Date()
        if downloadedChunks[index] {
            return true
        }
        if let existing = inFlight[index] {
            return await existing.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.downloadChunk(index: index)
        }
        inFlight[index] = task
        let result = await task.value
        inFlight.removeValue(forKey: index)
        return result
    }

    func readSlice(offset: Int64, length: Int) -> Data? {
        guard let fileHandle, offset >= 0, length > 0 else { return nil }
        lastAccessedAt = Date()
        do {
            try fileHandle.seek(toOffset: UInt64(offset))
            return try fileHandle.read(upToCount: length)
        } catch {
            return nil
        }
    }

    private func downloadChunk(index: Int) async -> Bool {
        let start = Int64(index) * Int64(LocalAudioProxy.chunkSize)
        let end = min(totalBytes - 1, start + Int64(LocalAudioProxy.chunkSize) - 1)
        let expectedLen = Int(end - start + 1)
        guard expectedLen > 0 else { return false }

        var attemptedRefresh = false
        for _ in 0..<2 {
            let candidateURLs = [descriptor.url] + LocalAudioProxy.buildFailoverURLs(for: descriptor.url)
            var sawAuthExpiry = false

            for url in candidateURLs {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                for (k, v) in descriptor.headers {
                    req.setValue(v, forHTTPHeaderField: k)
                }

                do {
                    let (rawData, response) = try await session.data(for: req)
                    guard let http = response as? HTTPURLResponse else { continue }
                    if http.statusCode == 403 || http.statusCode == 410 {
                        sawAuthExpiry = true
                        break
                    }
                    guard http.statusCode == 206 || (http.statusCode == 200 && index == 0 && rawData.count >= expectedLen) else {
                        continue
                    }

                    let slice = rawData.count == expectedLen ? rawData : rawData.prefix(expectedLen)
                    guard slice.count == expectedLen else { continue }

                    var bytesToWrite = Data(slice)
                    if index == 0 && descriptor.isMp4Container {
                        let normalized = MP4DurationNormalizer.normalizeFragmentedMp4Header(bytesToWrite)
                        if normalized.data.count == expectedLen {
                            bytesToWrite = normalized.data
                        }
                    }

                    guard writeChunkToDisk(offset: start, data: bytesToWrite) else { return false }
                    downloadedChunks[index] = true
                    await promoteIfComplete()
                    return true
                } catch {
                    continue
                }
            }

            if sawAuthExpiry && !attemptedRefresh, let refresh = onRefresh {
                attemptedRefresh = true
                if let fresh = await refresh(descriptor.trackId),
                   fresh.contentLength == nil || fresh.contentLength == totalBytes {
                    self.descriptor = fresh
                    continue
                }
            }
            break
        }
        return false
    }

    private func writeChunkToDisk(offset: Int64, data: Data) -> Bool {
        guard let fileHandle else { return false }
        do {
            try fileHandle.seek(toOffset: UInt64(offset))
            try fileHandle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private func promoteIfComplete() async {
        guard !promotedToPersistentCache, downloadedChunks.allSatisfy({ $0 }) else { return }
        promotedToPersistentCache = true
        try? fileHandle?.synchronize()
        _ = try? await cache.copyCompletedFile(
            mediaId: descriptor.trackId,
            from: fileURL,
            fileExtension: descriptor.fileExtension
        )
    }
}
