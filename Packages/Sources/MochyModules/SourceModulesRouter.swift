import Foundation
import MochyCore
import MochyInnerTube

public enum SourceResolutionError: Error, LocalizedError {
    case offlineUnavailable
    case failedAllSources(String)

    public var errorDescription: String? {
        switch self {
        case .offlineUnavailable:
            return "Offline mode is enabled and this track is not downloaded locally."
        case let .failedAllSources(msg):
            return "All audio sources failed: \(msg)"
        }
    }
}

/// Multi-source router implementing Mochy Music's Just-In-Time resolution order:
/// 1) Local / Offline bypass, 2) Forced route (`ProviderSwitch`), 3) Parallel speculative walk ahead of YouTube, 4) YouTube (`YTPlayerResolver`).
public actor SourceModulesRouter {
    private static let moduleTimeoutNs: UInt64 = 3_500_000_000
    private static let failedSourceMemorySeconds: TimeInterval = 10 * 60

    private let youtubeResolver: YTPlayerResolver
    private var modules: [String: any MochyStreamModule]
    private var forcedRoutes: [String: String] = [:]
    private var failedSources: [String: Date] = [:] // key = "\(sourceId):\(trackId)"

    public init(
        youtubeResolver: YTPlayerResolver = YTPlayerResolver(),
        modules: [any MochyStreamModule] = [MonochromeModule(), JioSaavnModule(), AppleMusicModule()]
    ) {
        self.youtubeResolver = youtubeResolver
        var map: [String: any MochyStreamModule] = [:]
        for mod in modules {
            map[mod.id] = mod
        }
        self.modules = map
    }

    public func registerModule(_ module: any MochyStreamModule) {
        modules[module.id] = module
    }

    public func unregisterModule(id: String) {
        modules.removeValue(forKey: id)
    }

    public func registeredModuleIds() -> [String] {
        Array(modules.keys).sorted()
    }

    public func setForcedRoute(trackId: String, sourceId: String?) {
        forcedRoutes[trackId] = sourceId
    }

    public func markSourceFailed(sourceId: String, trackId: String) {
        failedSources["\(sourceId):\(trackId)"] = Date()
    }

    public func resolve(
        track: ModuleTrack,
        quality: AudioQuality = .high,
        preferMp4OnIOS: Bool = true,
        sourceOrder: [String] = ["youtube", "monochrome", "jiosaavn"],
        offlineMode: Bool = false,
        downloadedFileURL: URL? = nil
    ) async throws -> ModuleStream {
        // Step 1: Device & Offline bypass
        if let localURL = track.localFileURL {
            return ModuleStream(
                url: localURL,
                codec: localURL.pathExtension.uppercased(),
                sourceId: "local",
                sourceLabel: "This device",
                qualityBadge: "Local Audio"
            )
        }
        if let downloadedFileURL, FileManager.default.fileExists(atPath: downloadedFileURL.path) {
            return ModuleStream(
                url: downloadedFileURL,
                codec: "Cached",
                sourceId: "downloads",
                sourceLabel: "Your downloads",
                qualityBadge: "Offline Cached"
            )
        }
        if offlineMode {
            throw SourceResolutionError.offlineUnavailable
        }

        // Step 2: Forced Route (`ProviderSwitch`)
        if let forcedSource = forcedRoutes[track.id] {
            if forcedSource == "youtube" {
                return try await resolveYouTube(track: track, quality: quality, preferMp4OnIOS: preferMp4OnIOS)
            }
            if let mod = modules[forcedSource],
               let forced = try? await mod.resolve(track: track, quality: quality) {
                return forced
            }
        }

        // Step 3: Parallel speculative walk for all modules ranked ahead of "youtube"
        let youtubeIndex = sourceOrder.firstIndex(of: "youtube") ?? sourceOrder.count
        let preYoutubeIds = Array(sourceOrder.prefix(youtubeIndex)).filter { sourceId in
            guard modules[sourceId] != nil else { return false }
            if let failedAt = failedSources["\(sourceId):\(track.id)"],
               Date().timeIntervalSince(failedAt) < Self.failedSourceMemorySeconds {
                return false
            }
            return true
        }

        if !preYoutubeIds.isEmpty {
            let activeModules = preYoutubeIds.compactMap { id in modules[id].map { (id, $0) } }
            if let winner = await raceModulesInOrder(track: track, quality: quality, orderedModules: activeModules) {
                return winner
            }
            for id in preYoutubeIds {
                failedSources["\(id):\(track.id)"] = Date()
            }
        }

        // Step 4: YouTube InnerTube fallback (always authoritative fallback)
        do {
            return try await resolveYouTube(track: track, quality: quality, preferMp4OnIOS: preferMp4OnIOS)
        } catch {
            throw SourceResolutionError.failedAllSources(error.localizedDescription)
        }
    }

    private func raceModulesInOrder(
        track: ModuleTrack,
        quality: AudioQuality,
        orderedModules: [(String, any MochyStreamModule)]
    ) async -> ModuleStream? {
        await withTaskGroup(of: (Int, ModuleStream?).self) { group in
            for (idx, pair) in orderedModules.enumerated() {
                group.addTask {
                    let result = try? await pair.1.resolve(track: track, quality: quality)
                    return (idx, result)
                }
            }

            // Timeout watchdog
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.moduleTimeoutNs)
                return (-1, nil)
            }

            var received: [Int: ModuleStream?] = [:]
            var nextNeededIndex = 0

            for await (idx, stream) in group {
                if idx == -1 {
                    // Timeout reached; return best received in order so far
                    for checkIdx in 0..<orderedModules.count {
                        if let found = received[checkIdx] ?? nil {
                            group.cancelAll()
                            return found
                        }
                    }
                    group.cancelAll()
                    return nil
                }

                received[idx] = stream
                while nextNeededIndex < orderedModules.count, let entry = received[nextNeededIndex] {
                    if let valid = entry {
                        group.cancelAll()
                        return valid
                    }
                    nextNeededIndex += 1
                }
                if nextNeededIndex == orderedModules.count {
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
    }

    private func resolveYouTube(
        track: ModuleTrack,
        quality: AudioQuality,
        preferMp4OnIOS: Bool
    ) async throws -> ModuleStream {
        let resolved = try await youtubeResolver.resolveStream(
            videoId: track.id,
            quality: quality,
            preferMp4: preferMp4OnIOS
        )
        let kbps = resolved.format.bitrate / 1000
        let lowerMime = resolved.format.mimeType.lowercased()
        let codecName = lowerMime.contains("opus") ? "Opus" : "AAC"
        let cleanMime = lowerMime.split(separator: ";").first.map(String.init) ?? "audio/mp4"
        return ModuleStream(
            url: resolved.streamURL,
            headers: resolved.requiredHeaders,
            format: .progressive,
            codec: codecName,
            mimeType: cleanMime,
            contentLength: resolved.verifiedContentLength ?? resolved.format.contentLength,
            durationSeconds: resolved.authoritativeDurationSeconds ?? track.durationSeconds,
            sampleRate: resolved.format.audioSampleRate,
            bitDepth: 16,
            bitrate: resolved.format.bitrate,
            sourceId: "youtube",
            sourceLabel: "YouTube (\(resolved.clientUsed.friendlyName ?? resolved.clientUsed.clientName))",
            qualityBadge: "\(codecName) \(kbps) kbps",
            isDRM: false,
            loudnessDb: resolved.loudnessDb
        )
    }
}
