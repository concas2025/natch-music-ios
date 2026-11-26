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

/// Faithful port of Mochy Music's `YTPlayerUtils.kt` stream resolution, client fallback,
/// format ranking, EJS deobfuscation, PoToken attachment, and last-byte cutoff validator.
public actor YTPlayerResolver {
    public typealias StreamValidator = @Sendable (URL, YouTubeClient, Int64?, String?) async -> Bool

    private static let premiumAudioItags: Set<Int> = [141, 774, 327, 328, 380, 256, 258]
    private static let premiumBitrateThreshold = 220_000
    private static let visionOSRestDuration: TimeInterval = 30 * 60

    private let innerTube: InnerTubeClient
    private let ejsSolver: EjsSolver
    private let poTokenGenerator: PoTokenGenerator
    private let session: URLSession
    private let customValidator: StreamValidator?

    private var visionOSBotChecks = 0
    private var visionOSRestUntil: Date = .distantPast

    public init(
        innerTube: InnerTubeClient = InnerTubeClient(),
        ejsSolver: EjsSolver = EjsSolver(),
        poTokenGenerator: PoTokenGenerator = PoTokenGenerator(),
        session: URLSession = .shared,
        customValidator: StreamValidator? = nil
    ) {
        self.innerTube = innerTube
        self.ejsSolver = ejsSolver
        self.poTokenGenerator = poTokenGenerator
        self.session = session
        self.customValidator = customValidator
    }

    internal func resolveRawPlayer(client: YouTubeClient, videoId: String) async throws -> PlayerResponse {
        let ts = client.useSignatureTimestamp ? (try? await ejsSolver.currentSignatureTimestamp()) : nil
        return try await innerTube.player(client: client, videoId: videoId, signatureTimestamp: ts)
    }

    public func resolveStream(
        videoId: String,
        playlistId: String? = nil,
        quality: AudioQuality = .high,
        preferMp4: Bool = true
    ) async throws -> ResolvedStream {
        let cookie = await innerTube.cookie
        let isLoggedIn = !(cookie?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let visitor = await innerTube.visitorData

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
                if client.useWebPoTokens && poTokenResult == nil, let sessionId = visitor ?? cookie {
                    poTokenResult = await poTokenGenerator.poTokenFor(videoId: videoId, sessionId: sessionId)
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
                    let isValid = await validateStream(
                        url: streamURL,
                        client: client,
                        contentLength: format.contentLength,
                        cookie: activeCookie
                    )
                    if isValid {
                        return ResolvedStream(
                            videoId: videoId,
                            streamURL: streamURL,
                            format: format,
                            clientUsed: client,
                            loudnessDb: response.playerConfig?.audioConfig?.loudnessDb ?? format.loudnessDb,
                            perceptualLoudnessDb: response.playerConfig?.audioConfig?.perceptualLoudnessDb,
                            expiresInSeconds: streamingData.expiresInSeconds,
                            requiredHeaders: Self.streamHeaders(for: client, cookie: activeCookie),
                            videoDetails: response.videoDetails
                        )
                    }
                }
                break
            }
        }

        throw YTPlayerResolverError.noPlayableStream(lastReason: lastReason)
    }

    // MARK: - Format Ranking

    public static func selectCandidateFormats(
        from formats: [PlayerResponse.StreamingData.Format],
        quality: AudioQuality,
        preferMp4: Bool = true
    ) -> [PlayerResponse.StreamingData.Format] {
        let audioOnly = formats.filter { $0.isAudio }
        guard !audioOnly.isEmpty else { return [] }

        let originals = audioOnly.filter { $0.isOriginal }
        let pool = originals.isEmpty ? audioOnly : originals

        let filtered: [PlayerResponse.StreamingData.Format]
        if let maxBitrate = quality.maxBitrate {
            let underCap = pool.filter { $0.bitrate <= maxBitrate }
            filtered = underCap.isEmpty ? pool : underCap
        } else {
            filtered = pool
        }

        return filtered.sorted { lhs, rhs in
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

            // shortcut: prefers audio/mp4 over audio/webm until Phase 2 adds FFmpeg/Opus demuxer; remove preference once WebM playback is wired.
            let lCodec = codecRank(lhs.mimeType, preferMp4: preferMp4)
            let rCodec = codecRank(rhs.mimeType, preferMp4: preferMp4)
            if lCodec != rCodec { return lCodec > rCodec }

            let lDirect = lhs.url != nil
            let rDirect = rhs.url != nil
            if lDirect != rDirect { return lDirect }

            return (lhs.audioSampleRate ?? 0) > (rhs.audioSampleRate ?? 0)
        }
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

    private func resolveFormatURL(format: PlayerResponse.StreamingData.Format) async throws -> String {
        if let direct = format.url, !direct.isEmpty {
            return (try? await ejsSolver.transformNParam(in: direct)) ?? direct
        }
        if let cipher = format.signatureCipher ?? format.cipher {
            return try await ejsSolver.deobfuscateStreamURL(signatureCipher: cipher)
        }
        throw EjsSolverError.invalidCipherParameters
    }

    private func validateStream(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?
    ) async -> Bool {
        if let customValidator {
            return await customValidator(url, client, contentLength, cookie)
        }
        return await Self.validateStreamURL(
            url: url,
            client: client,
            contentLength: contentLength,
            cookie: cookie,
            session: session
        )
    }

    /// Probes the final byte (`Range: bytes={len-1}-{len-1}`) so untokened ~786 KB cutoffs fail fast.
    public static func validateStreamURL(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?,
        session: URLSession
    ) async -> Bool {
        let request = buildValidationRequest(
            url: url,
            client: client,
            contentLength: contentLength,
            cookie: cookie
        )
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 200 || http.statusCode == 206 {
                return true
            }
            if http.statusCode == 416 && contentLength == nil {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    public static func buildValidationRequest(
        url: URL,
        client: YouTubeClient,
        contentLength: Int64?,
        cookie: String?
    ) -> URLRequest {
        let probeOffset = max(0, (contentLength ?? 1_048_577) - 1)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(probeOffset)-\(probeOffset)", forHTTPHeaderField: "Range")
        for (header, value) in streamHeaders(for: client, cookie: cookie) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    public static func streamHeaders(for client: YouTubeClient, cookie: String?) -> [String: String] {
        var headers = ["User-Agent": client.userAgent]
        if !client.isNativeApp {
            headers["Origin"] = client.apiOrigin
            headers["Referer"] = "\(client.apiOrigin)/"
        }
        if let cookie, !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        return headers
    }
}
