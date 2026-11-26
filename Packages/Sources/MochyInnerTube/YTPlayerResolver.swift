import Foundation
import MochyCore

public struct ResolvedStream: Sendable, Equatable {
    public let videoId: String
    public let streamURL: URL
    public let format: PlayerResponse.StreamingData.Format
    public let clientUsed: YouTubeClient
    public let loudnessDb: Double?
    public let perceptualLoudnessDb: Double?
    public let expiresInSeconds: Int
    public let requiredHeaders: [String: String]
    public let videoDetails: PlayerResponse.VideoDetails?
    public let verifiedContentLength: Int64?

    public init(
        videoId: String,
        streamURL: URL,
        format: PlayerResponse.StreamingData.Format,
        clientUsed: YouTubeClient,
        loudnessDb: Double?,
        perceptualLoudnessDb: Double?,
        expiresInSeconds: Int,
        requiredHeaders: [String: String],
        videoDetails: PlayerResponse.VideoDetails?,
        verifiedContentLength: Int64? = nil
    ) {
        self.videoId = videoId
        self.streamURL = streamURL
        self.format = format
        self.clientUsed = clientUsed
        self.loudnessDb = loudnessDb
        self.perceptualLoudnessDb = perceptualLoudnessDb
        self.expiresInSeconds = expiresInSeconds
        self.requiredHeaders = requiredHeaders
        self.videoDetails = videoDetails
        self.verifiedContentLength = verifiedContentLength
    }

    public var authoritativeDurationSeconds: Int? {
        if let rawLen = videoDetails?.lengthSeconds, let secs = Int(rawLen), secs > 0 {
            return secs
        }
        if let approxMs = format.approxDurationMs, let ms = Int(approxMs), ms > 0 {
            return ms / 1000
        }
        return nil
    }
}

public enum YTPlayerResolverError: Error, LocalizedError {
    case offline
    case noPlayableStream(lastReason: String?)

    public var errorDescription: String? {
        switch self {
        case .offline:
            return "No network connectivity available."
        case let .noPlayableStream(lastReason):
            return "Could not resolve any playable stream\(lastReason.map { ": \($0)" } ?? ".")."
        }
    }
}

/// Faithful port of Mochy Music's `YTPlayerUtils.kt` hardened with battle-tested iOS streaming rules:
/// - Strict MP4/AAC filtering for iOS `AVPlayer` + muxed progressive `itag 18` fallback
/// - Single-RTT `1.15 MB` Range cutoff probe rejecting HTTP 416 / 403 ~1:30 stream drops
/// - Real guest `visitorData` & `dataSyncId` session binding for BotGuard `PoTokenGenerator`
/// - Stand-in alternate upload lookup (`orStandIn`) & studio audio swap (`studioVersionOf`)
public actor YTPlayerResolver {
    public typealias StreamValidator = @Sendable (URL, YouTubeClient, Int64?, String?) async -> Bool

    public static let past1MiBProbeOffset: Int64 = 1_150_000
    private static let premiumAudioItags: Set<Int> = [141, 774, 327, 328, 380, 256, 258]
    private static let premiumBitrateThreshold = 220_000
    private static let visionOSRestDuration: TimeInterval = 30 * 60

    internal let innerTube: InnerTubeClient
    internal let ejsSolver: EjsSolver
    private let poTokenGenerator: PoTokenGenerator
    private let session: URLSession
    private let customValidator: StreamValidator?

    private var visionOSBotChecks = 0
    private var visionOSRestUntil: Date = .distantPast
    private var studioIdCache: [String: String] = [:]

    public init(
        innerTube: InnerTubeClient = InnerTubeClient(),
        ejsSolver: EjsSolver = EjsSolver(),
        poTokenGenerator: PoTokenGenerator = PoTokenGenerator(),
        session: URLSession? = nil,
        customValidator: StreamValidator? = nil
    ) {
        self.innerTube = innerTube
        self.ejsSolver = ejsSolver
        self.poTokenGenerator = poTokenGenerator
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 6
            cfg.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: cfg)
        }
        self.customValidator = customValidator
    }

    public var hasActivePoToken: Bool {
        get async { await poTokenGenerator.hasSessionToken }
    }

    internal func resolveRawPlayer(client: YouTubeClient, videoId: String) async throws -> PlayerResponse {
        let ts = client.useSignatureTimestamp ? (try? await ejsSolver.currentSignatureTimestamp()) : nil
        return try await innerTube.player(client: client, videoId: videoId, signatureTimestamp: ts)
    }

    public func resolveStream(
        videoId: String,
        playlistId: String? = nil,
        quality: AudioQuality = .high,
        preferMp4: Bool = true,
        preferStudioForVideos: Bool = false
    ) async throws -> ResolvedStream {
        do {
            let primary = try await resolveSingleVideo(
                videoId: videoId,
                playlistId: playlistId,
                quality: quality,
                preferMp4: preferMp4
            )
            if preferStudioForVideos,
               let studio = await resolveStudioVersionIfMusicVideo(original: primary, quality: quality, preferMp4: preferMp4) {
                return studio
            }
            return primary
        } catch {
            // Stand-in lookup (`orStandIn`): if YouTube refused this upload, try alternate uploads of the same track.
            if let standIn = await tryStandInUploads(failedVideoId: videoId, quality: quality, preferMp4: preferMp4) {
                return standIn
            }
            throw error
        }
    }

    private func resolveSingleVideo(
        videoId: String,
        playlistId: String?,
        quality: AudioQuality,
        preferMp4: Bool
    ) async throws -> ResolvedStream {
        let cookie = await innerTube.cookie
        let isLoggedIn = !(cookie?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let dataSync = await innerTube.dataSyncId

        var clientOrder: [YouTubeClient] = []
        if Date() >= visionOSRestUntil {
            clientOrder.append(.visionOS)
        }
        if isLoggedIn {
            clientOrder.append(contentsOf: YouTubeClient.accountClients)
        }
        for fallback in YouTubeClient.streamFallbackClients where !clientOrder.contains(fallback) {
            if fallback.loginRequired && !isLoggedIn { continue }
            clientOrder.append(fallback)
        }

        var lastReason: String?
        var cachedSignatureTimestamp: Int?
        var poTokenResult: PoTokenResult?

        for client in clientOrder {
            var attemptsForClient = client == .visionOS ? 2 : 1
            while attemptsForClient > 0 {
                attemptsForClient -= 1

                if client.useSignatureTimestamp && cachedSignatureTimestamp == nil {
                    cachedSignatureTimestamp = try? await ejsSolver.currentSignatureTimestamp()
                }
                if client.useWebPoTokens && poTokenResult == nil {
                    let guestVisitor = await innerTube.ensureGuestVisitorData()
                    let poSessionId = (isLoggedIn ? dataSync : nil) ?? guestVisitor
                    if let poSessionId, !poSessionId.isEmpty {
                        poTokenResult = await poTokenGenerator.poTokenFor(videoId: videoId, sessionId: poSessionId)
                    }
                }

                let response: PlayerResponse
                do {
                    response = try await innerTube.player(
                        client: client,
                        videoId: videoId,
                        playlistId: playlistId,
                        signatureTimestamp: client.useSignatureTimestamp ? cachedSignatureTimestamp : nil,
                        poToken: client.useWebPoTokens ? poTokenResult?.playerRequestPoToken : nil,
                        setLogin: isLoggedIn && client.loginSupported
                    )
                } catch {
                    lastReason = error.localizedDescription
                    break
                }

                guard response.playabilityStatus.status == "OK", let streamingData = response.streamingData else {
                    lastReason = response.playabilityStatus.reason ?? response.playabilityStatus.status
                    if client == .visionOS && Self.looksLikeBotCheck(response.playabilityStatus) {
                        visionOSBotChecks += 1
                        await innerTube.invalidateOwnVisitorId(for: .visionOS)
                        if visionOSBotChecks >= 2 {
                            visionOSRestUntil = Date().addingTimeInterval(Self.visionOSRestDuration)
                            visionOSBotChecks = 0
                            break
                        }
                        continue
                    }
                    break
                }

                if client == .visionOS {
                    visionOSBotChecks = 0
                }

                let candidates = Self.selectCandidateFormats(
                    from: streamingData.adaptiveFormats + (streamingData.formats ?? []),
                    quality: quality,
                    preferMp4: preferMp4
                )

                for format in candidates {
                    guard var rawURL = try? await resolveFormatURL(format: format) else {
                        continue
                    }
                    if client.useWebPoTokens, let streamPot = poTokenResult?.streamingDataPoToken {
                        let sep = rawURL.contains("?") ? "&" : "?"
                        rawURL += "\(sep)pot=\(streamPot)"
                    }
                    guard let streamURL = URL(string: rawURL) else {
                        continue
                    }

                    let activeCookie = (isLoggedIn && client.loginSupported) ? cookie : nil
                    let validation = await validateAndMeasureStream(
                        url: streamURL,
                        client: client,
                        contentLength: format.contentLength,
                        cookie: activeCookie
                    )
                    if validation.isValid {
                        return ResolvedStream(
                            videoId: videoId,
                            streamURL: streamURL,
                            format: format,
                            clientUsed: client,
                            loudnessDb: response.playerConfig?.audioConfig?.loudnessDb ?? format.loudnessDb,
                            perceptualLoudnessDb: response.playerConfig?.audioConfig?.perceptualLoudnessDb,
                            expiresInSeconds: streamingData.expiresInSeconds,
                            requiredHeaders: Self.streamHeaders(for: client, cookie: activeCookie),
                            videoDetails: response.videoDetails,
                            verifiedContentLength: validation.measuredLength ?? format.contentLength
                        )
                    }
                }
                break
            }
        }

        throw YTPlayerResolverError.noPlayableStream(lastReason: lastReason)
    }

    // MARK: - Stand-In Uploads & Studio Audio Swap

    private func tryStandInUploads(failedVideoId: String, quality: AudioQuality, preferMp4: Bool) async -> ResolvedStream? {
        guard let meta = try? await innerTube.player(client: .metadataClient, videoId: failedVideoId),
              let details = meta.videoDetails,
              let title = details.title, !title.isEmpty,
              let author = details.author, !author.isEmpty else {
            return nil
        }
        let cleanAuthor = author.replacingOccurrences(of: " - Topic", with: "")
        let results = (try? await innerTube.searchTracks(query: "\(TrackMatcher.core(title)) \(cleanAuthor)")) ?? []
        let targetDur = Int(details.lengthSeconds)
        let query = TrackQuery(title: title, artist: cleanAuthor, durationSeconds: targetDur)

        let alternates = results.filter { $0.id != failedVideoId }.compactMap { item -> (YTTrackItem, Double)? in
            let cand = TrackCandidate(item: item, title: item.title, artist: item.artistDisplay, durationSeconds: item.durationSeconds)
            let s = TrackMatcher.score(query: query, candidate: cand)
            return s >= 0.72 ? (item, s) : nil
        }.sorted { $0.1 > $1.1 }.prefix(2)

        for (alt, _) in alternates {
            if let resolved = try? await resolveSingleVideo(videoId: alt.id, playlistId: nil, quality: quality, preferMp4: preferMp4) {
                return ResolvedStream(
                    videoId: failedVideoId,
                    streamURL: resolved.streamURL,
                    format: resolved.format,
                    clientUsed: resolved.clientUsed,
                    loudnessDb: resolved.loudnessDb,
                    perceptualLoudnessDb: resolved.perceptualLoudnessDb,
                    expiresInSeconds: resolved.expiresInSeconds,
                    requiredHeaders: resolved.requiredHeaders,
                    videoDetails: details,
                    verifiedContentLength: resolved.verifiedContentLength
                )
            }
        }
        return nil
    }

    private func resolveStudioVersionIfMusicVideo(
        original: ResolvedStream,
        quality: AudioQuality,
        preferMp4: Bool
    ) async -> ResolvedStream? {
        guard let details = original.videoDetails,
              let mvType = details.musicVideoType,
              mvType != "MUSIC_VIDEO_TYPE_ATV",
              let title = details.title,
              let author = details.author else {
            return nil
        }
        let studioId: String
        if let cached = studioIdCache[original.videoId] {
            guard !cached.isEmpty else { return nil }
            studioId = cached
        } else {
            let cleanAuthor = author.replacingOccurrences(of: " - Topic", with: "")
            let candidates = (try? await innerTube.searchTracks(query: "\(TrackMatcher.core(title)) \(cleanAuthor)")) ?? []
            let query = TrackQuery(title: title, artist: cleanAuthor, durationSeconds: Int(details.lengthSeconds))
            let best = TrackMatcher.bestMatch(
                query: query,
                candidates: candidates
                    .filter { $0.id != original.videoId }
                    .map { TrackCandidate(item: $0.id, title: $0.title, artist: $0.artistDisplay, durationSeconds: $0.durationSeconds) },
                threshold: 0.78
            )
            studioIdCache[original.videoId] = best?.candidate ?? ""
            guard let foundId = best?.candidate else { return nil }
            studioId = foundId
        }

        guard let studio = try? await resolveSingleVideo(videoId: studioId, playlistId: nil, quality: quality, preferMp4: preferMp4) else {
            return nil
        }
        return ResolvedStream(
            videoId: original.videoId,
            streamURL: studio.streamURL,
            format: studio.format,
            clientUsed: studio.clientUsed,
            loudnessDb: studio.loudnessDb,
            perceptualLoudnessDb: studio.perceptualLoudnessDb,
            expiresInSeconds: studio.expiresInSeconds,
            requiredHeaders: studio.requiredHeaders,
            videoDetails: details,
            verifiedContentLength: studio.verifiedContentLength
        )
    }

    // MARK: - Format Ranking (iOS AVPlayer Safe + Progressive itag 18 Fallback)

    public static func selectCandidateFormats(
        from formats: [PlayerResponse.StreamingData.Format],
        quality: AudioQuality,
        preferMp4: Bool = true
    ) -> [PlayerResponse.StreamingData.Format] {
        let audioOnly = formats.filter { $0.isAudio }
        let originals = audioOnly.filter { $0.isOriginal }
        let baseAudioPool = originals.isEmpty ? audioOnly : originals

        // On iOS (`preferMp4 == true`), AVPlayer cannot decode Matroska/WebM containers directly;
        // exclude `audio/webm` so playback never silently fails, and append progressive `itag 18` as last-resort fallback.
        let containerSafePool: [PlayerResponse.StreamingData.Format]
        if preferMp4 {
            containerSafePool = baseAudioPool.filter { isNativeIOSAudioContainer($0.mimeType) }
        } else {
            containerSafePool = baseAudioPool
        }

        let filtered: [PlayerResponse.StreamingData.Format]
        if let maxBitrate = quality.maxBitrate {
            let underCap = containerSafePool.filter { $0.bitrate <= maxBitrate }
            filtered = underCap.isEmpty ? containerSafePool : underCap
        } else {
            filtered = containerSafePool
        }

        var ranked = filtered.sorted { lhs, rhs in
            let lQuality = audioQualityRank(lhs.audioQuality)
            let rQuality = audioQualityRank(rhs.audioQuality)
            if lQuality != rQuality { return lQuality > rQuality }

            let lPremium = isPremiumAudioFormat(lhs)
            let rPremium = isPremiumAudioFormat(rhs)
            if lPremium != rPremium { return lPremium }

            let lChannels = lhs.audioChannels ?? 2
            let rChannels = rhs.audioChannels ?? 2
            if lChannels != rChannels { return lChannels > rChannels }

            if lhs.bitrate != rhs.bitrate { return lhs.bitrate > rhs.bitrate }

            let lCodec = codecRank(lhs.mimeType, preferMp4: preferMp4)
            let rCodec = codecRank(rhs.mimeType, preferMp4: preferMp4)
            if lCodec != rCodec { return lCodec > rCodec }

            let lDirect = lhs.url != nil
            let rDirect = rhs.url != nil
            if lDirect != rDirect { return lDirect }

            return (lhs.audioSampleRate ?? 0) > (rhs.audioSampleRate ?? 0)
        }

        // Progressive muxed MP4 (`itag 18`, stereo AAC inside `video/mp4`) is uncapped on iOS even when adaptive streams fail.
        let progressiveFallbacks = formats.filter {
            $0.itag == 18 && $0.mimeType.lowercased().contains("mp4") && !ranked.contains($0)
        }
        ranked.append(contentsOf: progressiveFallbacks)
        return ranked
    }

    public static func isNativeIOSAudioContainer(_ mimeType: String) -> Bool {
        let lower = mimeType.lowercased()
        if lower.contains("webm") || lower.contains("matroska") { return false }
        return lower.contains("audio/mp4")
            || lower.contains("mp4a")
            || lower.contains("audio/aac")
            || lower.contains("audio/mpeg")
            || lower.contains("audio/flac")
    }

    public static func isPremiumAudioFormat(_ format: PlayerResponse.StreamingData.Format) -> Bool {
        premiumAudioItags.contains(format.itag) || format.bitrate >= premiumBitrateThreshold
    }

    private static func audioQualityRank(_ quality: String?) -> Int {
        switch quality {
        case "AUDIO_QUALITY_HIGH": return 3
        case "AUDIO_QUALITY_MEDIUM": return 2
        case "AUDIO_QUALITY_LOW": return 1
        default: return 0
        }
    }

    private static func codecRank(_ mimeType: String, preferMp4: Bool) -> Int {
        let lower = mimeType.lowercased()
        if preferMp4 {
            if lower.contains("audio/mp4") || lower.contains("mp4a") { return 2 }
            if lower.contains("opus") || lower.contains("webm") { return 1 }
        } else {
            if lower.contains("opus") || lower.contains("webm") { return 2 }
            if lower.contains("audio/mp4") || lower.contains("mp4a") { return 1 }
        }
        return 0
    }

    private static func looksLikeBotCheck(_ status: PlayerResponse.PlayabilityStatus) -> Bool {
        if status.status == "LOGIN_REQUIRED" { return true }
        let reason = status.reason?.lowercased() ?? ""
        return reason.contains("bot") || reason.contains("sign in")
    }

    // MARK: - URL Construction & Range Validation

    internal func resolveFormatURL(format: PlayerResponse.StreamingData.Format) async throws -> String {
        if let direct = format.url, !direct.isEmpty {
            return (try? await ejsSolver.transformNParam(in: direct)) ?? direct
        }
        if let cipher = format.signatureCipher ?? format.cipher {
            return try await ejsSolver.deobfuscateStreamURL(signatureCipher: cipher)
        }
        throw EjsSolverError.invalidCipherParameters
    }

    private func validateAndMeasureStream(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?
    ) async -> (isValid: Bool, measuredLength: Int64?) {
        if let customValidator {
            let ok = await customValidator(url, client, contentLength, cookie)
            return (ok, contentLength)
        }
        return await Self.validateAndMeasureStreamURL(
            url: url,
            client: client,
            contentLength: contentLength,
            cookie: cookie,
            session: session
        )
    }

    /// Probes past the ~1 MiB untokened cutoff (`1,150,000`) when `contentLength == nil` or probes the final byte
    /// when `contentLength` is known, rejecting HTTP 416 / 403 cutoff streams.
    public static func validateStreamURL(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?,
        session: URLSession
    ) async -> Bool {
        await validateAndMeasureStreamURL(
            url: url,
            client: client,
            contentLength: contentLength,
            cookie: cookie,
            session: session
        ).isValid
    }

    public static func validateAndMeasureStreamURL(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?,
        session: URLSession
    ) async -> (isValid: Bool, measuredLength: Int64?) {
        let request = buildValidationRequest(
            url: url,
            client: client,
            contentLength: contentLength,
            cookie: cookie
        )
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, nil) }
            if http.statusCode == 206 || http.statusCode == 200 {
                let totalFromRange = parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range"))
                let fallbackTotal = http.expectedContentLength > 0 ? http.expectedContentLength : nil
                return (true, totalFromRange ?? contentLength ?? fallbackTotal)
            }
            // Reject 416 / 403 / 404: 416 at 1.15 MB indicates a truncated ~786 KB untokened preview stream.
            return (false, nil)
        } catch {
            return (false, nil)
        }
    }

    public static func buildValidationRequest(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let contentLength, contentLength > 0 {
            let lastByte = contentLength - 1
            request.setValue("bytes=\(lastByte)-\(lastByte)", forHTTPHeaderField: "Range")
        } else {
            let start = past1MiBProbeOffset
            request.setValue("bytes=\(start)-\(start + 1)", forHTTPHeaderField: "Range")
        }
        for (header, value) in streamHeaders(for: client, cookie: cookie) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    public static func streamHeaders(for client: YouTubeClient, cookie: String?) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": client.userAgent,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        switch client.clientName {
        case "WEB_REMIX":
            headers["Origin"] = YouTubeClient.originYouTubeMusic
            headers["Referer"] = "\(YouTubeClient.originYouTubeMusic)/"
        case "WEB_CREATOR":
            headers["Origin"] = YouTubeClient.originYouTubeStudio
            headers["Referer"] = "\(YouTubeClient.originYouTubeStudio)/"
        default:
            headers["Origin"] = YouTubeClient.originYouTube
            headers["Referer"] = "\(YouTubeClient.originYouTube)/"
        }
        if let cookie, !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        return headers
    }

    private static func parseContentRangeTotal(_ header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        let suffix = header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Int64(suffix)
    }
}
