import AVFoundation
import Foundation
import MediaPlayer
import MochyCore
import MochyDatabase
import MochyDSP
import MochyInnerTube
import MochyModules
import Observation
#if os(iOS) && canImport(CoreHaptics)
import CoreHaptics
#endif
#if os(iOS) && canImport(MusicKit)
import MusicKit
#endif
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum RepeatMode: String, CaseIterable, Codable, Sendable {
    case off
    case all
    case one
}

public struct PlaybackItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Int?
    public let thumbnailURL: String?
    public let isrc: String?
    public let localFileURL: URL?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil,
        thumbnailURL: String? = nil,
        isrc: String? = nil,
        localFileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.isrc = isrc
        self.localFileURL = localFileURL
    }

    public init(ytTrack: YTTrackItem) {
        self.init(
            id: ytTrack.id,
            title: ytTrack.title,
            artist: ytTrack.artistDisplay,
            album: ytTrack.album,
            durationSeconds: ytTrack.durationSeconds,
            thumbnailURL: ytTrack.thumbnailURL
        )
    }

    public init(song: SongEntity, artistNames: [String]) {
        self.init(
            id: song.id,
            title: song.title,
            artist: artistNames.isEmpty ? "Unknown Artist" : artistNames.joined(separator: ", "),
            album: song.albumName,
            durationSeconds: song.duration > 0 ? song.duration : nil,
            thumbnailURL: song.thumbnailUrl,
            localFileURL: Self.resolveLocalURI(song.localUri)
        )
    }

    /// Resolves both relative paths inside `ApplicationSupport/LocalAudio` (survives iOS container UUID updates)
    /// and legacy `file://` URLs.
    public static func resolveLocalURI(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("relative://") {
            let rel = String(raw.dropFirst("relative://".count))
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let resolved = appSupport.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
            return nil
        }
        return URL(string: raw)
    }
}

/// Unified Dual-Deck `AVPlayer` + `LocalAudioProxy` + Real-Time `MTAudioProcessingTap` C++ DSP Audio Controller.
/// Routes BOTH remote progressive/fMP4 streams and local audio files through inline C++ `MochyFXEngine`,
/// `MochyStageEngine` (KEMAR HRTF), `CrossmixEngine` (19 DJ styles), and `Accelerate` `vDSP` FFT.
@MainActor
@Observable
public final class MochyAudioPlayer {
    public private(set) var queue: [PlaybackItem] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var activeSourceId: String = ""
    public private(set) var activeSourceLabel: String = ""
    public private(set) var activeQualityBadge: String = ""
    public private(set) var activeStreamURL: URL?
    public private(set) var isDRMStream: Bool = false
    public private(set) var spectrumBins: [Float] = Array(repeating: 0, count: SpectrumAnalyzer.binCount)
    public private(set) var stageLevels: [Float] = Array(repeating: 0, count: 6)
    public private(set) var activeCrossmixStyle: CrossmixStyle = .silkBlend
    public private(set) var isCrossmixing: Bool = false
    public private(set) var lastError: String?
    public private(set) var sleepTimerRemainingSeconds: Int?
    public private(set) var activePlaylistId: String?

    public var shuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .off

    // Audio Lab DSP Controls (100% live via inline MTAudioProcessingTap)
    public var eqGainsDb: [Float] = Array(repeating: 0, count: 10) {
        didSet { syncDSPParameters() }
    }
    public var preampDb: Float = 0 {
        didSet { syncDSPParameters() }
    }
    public var bassBoostDb: Float = 0 {
        didSet { syncDSPParameters() }
    }
    public var trebleBoostDb: Float = 0 {
        didSet { syncDSPParameters() }
    }
    public var warmth: Float = 0 {
        didSet { syncDSPParameters() }
    }
    public var reverbMix: Float = 0 {
        didSet { syncDSPParameters() }
    }
    public var playbackSpeed: Float = 1.0 {
        didSet {
            let clamped = max(0.5, min(2.0, playbackSpeed))
            if isPlaying {
                activePlayer?.rate = clamped
            }
            updateNowPlayingInfo()
        }
    }
    public var stageParams = StageParameters() {
        didSet { syncDSPParameters() }
    }

    /// Hook provided by `AppCoordinator` to fetch Up Next radio recommendations when nearing the end of the queue.
    public var onRequestRadioContinuation: ((_ seedVideoId: String) async -> [PlaybackItem])?
    /// Hook fired when a track passes the Last.fm scrobble threshold (`min(50% duration, 240s)`).
    public var onTrackScrobbleEligible: ((_ item: PlaybackItem) -> Void)?

    public var currentItem: PlaybackItem? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    public let chunkCache: ChunkRangeCache
    public let localProxy: LocalAudioProxy

    private let settings: AppSettings
    private let router: SourceModulesRouter
    private let database: MochyDatabase

    // Dual-Deck `AVPlayer` slots with dedicated inline C++ DSP taps.
    private var primaryPlayer: AVPlayer?
    private var primaryDSPContext = RealtimeDeckDSPContext(enableStageAndSpectrum: true)
    private var primaryTimeObserver: Any?
    private var primaryEndObserver: NSObjectProtocol?
    private var primaryFailObserver: NSObjectProtocol?
    private var primaryStatusObservation: NSKeyValueObservation?

    private var secondaryPlayer: AVPlayer?
    private var secondaryDSPContext = RealtimeDeckDSPContext(enableStageAndSpectrum: true)

    private var activePlayer: AVPlayer? { primaryPlayer }
    private var trackLoudnessDb: Double?
    private var knownDurationSeconds: TimeInterval?

    private var loadGeneration: UInt64 = 0
    private var playRecordedForGeneration = false
    private var scrobbleFiredForGeneration = false
    private var recoveredMidTrackForGeneration = false
    private var isFetchingRadio = false
    private var wasPlayingBeforeInterruption = false

    private var crossmixTimer: Timer?
    private var crossmixInFlightForIndex: Int?
    private var spectrumTimer: Timer?
    private var sleepTimer: Timer?

    private var cachedArtworkSongId: String?
    private var cachedArtworkData: Data?
    private var sessionObservers: [NSObjectProtocol] = []

    #if os(iOS) && canImport(CoreHaptics)
    private var hapticEngine: CHHapticEngine?
    private var lastHapticBeatTime: TimeInterval = 0
    #endif

    public init(
        settings: AppSettings,
        router: SourceModulesRouter,
        database: MochyDatabase,
        chunkCache: ChunkRangeCache = ChunkRangeCache()
    ) {
        self.settings = settings
        self.router = router
        self.database = database
        self.chunkCache = chunkCache
        self.localProxy = LocalAudioProxy(cache: chunkCache)
        setupAudioSessionAndRemoteCommands()
        syncDSPParameters()
        startSpectrumPollingTimer()
    }

    // MARK: - Queue & Playback Transport

    public func playQueue(_ items: [PlaybackItem], startIndex: Int = 0, playlistId: String? = nil) {
        guard !items.isEmpty else { return }
        self.queue = items
        self.currentIndex = max(0, min(startIndex, items.count - 1))
        self.activePlaylistId = playlistId
        loadAndPlayCurrent()
    }

    public func appendToQueue(_ item: PlaybackItem) {
        queue.append(item)
        if queue.count == 1 {
            currentIndex = 0
            loadAndPlayCurrent()
        }
    }

    public func playNext(_ item: PlaybackItem) {
        if queue.isEmpty {
            playQueue([item], startIndex: 0)
            return
        }
        let insertIdx = min(currentIndex + 1, queue.count)
        queue.insert(item, at: insertIdx)
    }

    public func jumpToQueueIndex(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        loadAndPlayCurrent()
    }

    public func moveQueueItem(fromOffsets: IndexSet, toOffset: Int) {
        guard let currentId = currentItem?.id else { return }
        var copy = queue
        // Manual index move to avoid SwiftUI dependency inside MochyAudio.
        let moving = fromOffsets.sorted().map { copy[$0] }
        for idx in fromOffsets.sorted(by: >) {
            copy.remove(at: idx)
        }
        let adjustedTarget = min(copy.count, toOffset - fromOffsets.filter { $0 < toOffset }.count)
        copy.insert(contentsOf: moving, at: max(0, adjustedTarget))
        queue = copy
        if let newIdx = queue.firstIndex(where: { $0.id == currentId }) {
            currentIndex = newIdx
        }
    }

    public func removeQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removingCurrent = (index == currentIndex)
        queue.remove(at: index)
        if queue.isEmpty {
            stopAllDecks()
            currentIndex = 0
            isPlaying = false
            updateNowPlayingInfo()
            return
        }
        if index < currentIndex {
            currentIndex -= 1
        } else if removingCurrent {
            currentIndex = min(currentIndex, queue.count - 1)
            loadAndPlayCurrent()
        }
    }

    public func clearUpcomingQueue() {
        guard queue.indices.contains(currentIndex) else { return }
        let keep = queue[currentIndex]
        queue = [keep]
        currentIndex = 0
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func pause() {
        isPlaying = false
        cancelActiveCrossmix()
        if isDRMStream {
            #if os(iOS) && canImport(MusicKit)
            ApplicationMusicPlayer.shared.pause()
            #endif
        } else {
            primaryPlayer?.pause()
        }
        updateNowPlayingInfo()
    }

    public func resume() {
        guard currentItem != nil else { return }
        isPlaying = true
        if isDRMStream {
            #if os(iOS) && canImport(MusicKit)
            Task { try? await ApplicationMusicPlayer.shared.play() }
            #endif
        } else {
            primaryPlayer?.play()
            if abs(playbackSpeed - 1.0) > 0.01 {
                primaryPlayer?.rate = playbackSpeed
            }
        }
        updateNowPlayingInfo()
    }

    public func skipNext() {
        guard !queue.isEmpty else { return }
        cancelActiveCrossmix()
        if repeatMode == .one {
            seek(to: 0)
            if !isPlaying { resume() }
            return
        }
        if let nextIdx = computeNextIndex() {
            currentIndex = nextIdx
            loadAndPlayCurrent()
        } else {
            pause()
        }
    }

    public func skipPrevious() {
        if currentTime > 4.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        cancelActiveCrossmix()
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
        }
        loadAndPlayCurrent()
    }

    public func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, max(duration, 1)))
        currentTime = clamped
        if isDRMStream {
            #if os(iOS) && canImport(MusicKit)
            ApplicationMusicPlayer.shared.playbackTime = clamped
            #endif
        } else if let primaryPlayer {
            let target = CMTime(seconds: clamped, preferredTimescale: 600)
            primaryPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        updateNowPlayingInfo()
    }

    public func forceSwitchProvider(to providerId: String) {
        guard let item = currentItem else { return }
        let savedPos = currentTime
        Task {
            await router.setForcedRoute(trackId: item.id, sourceId: providerId)
            loadAndPlayCurrent(resumeAtSeconds: savedPos)
        }
    }

    /// Returns a readable local audio file URL for the current track (for LyricsAutoSync & Share Studio MP4 export).
    public func localAudioFileURLForCurrentTrack() async -> URL? {
        guard let item = currentItem else { return nil }
        if let local = item.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        return await localProxy.completedFileURL(forTrackId: item.id)
    }

    // MARK: - Sleep Timer

    public func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        sleepTimerRemainingSeconds = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rem = self.sleepTimerRemainingSeconds else { return }
                if rem <= 1 {
                    self.cancelSleepTimer()
                    self.pause()
                } else {
                    self.sleepTimerRemainingSeconds = rem - 1
                }
            }
        }
    }

    public func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemainingSeconds = nil
    }

    // MARK: - Real-Time C++ DSP Parameter Sync

    public func syncDSPParameters() {
        let params = makeBaselineFXParameters()
        let bypass = settings.audioPassEnabled
        primaryDSPContext.updateFX(params, bypassAll: bypass)

        var stg = stageParams
        stg.enabled = !bypass && settings.dspStageEnabled
        primaryDSPContext.updateStage(stg, enabled: stg.enabled)
    }

    private func makeBaselineFXParameters() -> MochyFXParameters {
        var params = MochyFXParameters()
        params.enabled = !settings.audioPassEnabled
        params.eqGainsDb = settings.dspEqEnabled ? eqGainsDb : Array(repeating: 0, count: 10)
        params.bassBoostDb = bassBoostDb
        params.trebleBoostDb = trebleBoostDb
        params.warmth = warmth
        params.reverbMix = reverbMix
        params.orbitRateHz = settings.dspOrbitEnabled ? 0.18 : 0.0

        var totalGainDb = preampDb
        if settings.loudnessNormalizationEnabled, let loudness = trackLoudnessDb {
            // Normalize tracks toward -14 LUFS target, capped cleanly to [-9, +6] dB.
            let delta = Float(max(-9.0, min(6.0, -14.0 - loudness)))
            totalGainDb += delta
        }
        params.replayGainDb = totalGainDb
        params.limiterEnabled = true
        params.crossmixGain = 1.0
        return params
    }

    // MARK: - Just-In-Time Track Preparation (Generation Guarded)

    private func loadAndPlayCurrent(resumeAtSeconds: TimeInterval = 0) {
        guard let item = currentItem else { return }
        loadGeneration &+= 1
        let gen = loadGeneration
        playRecordedForGeneration = false
        scrobbleFiredForGeneration = false
        recoveredMidTrackForGeneration = false
        crossmixInFlightForIndex = nil
        lastError = nil
        isBuffering = true
        currentTime = resumeAtSeconds
        knownDurationSeconds = item.durationSeconds.map(TimeInterval.init)
        duration = knownDurationSeconds ?? 0
        stopAllDecks()
        primaryDSPContext.resetState()

        fetchAndCacheArtwork(for: item)
        maybeAppendRadioContinuation()

        Task {
            do {
                let resolved = try await resolvePlayableStream(for: item)
                guard gen == self.loadGeneration else { return }

                self.activeSourceId = resolved.sourceId
                self.activeSourceLabel = resolved.sourceLabel
                self.activeQualityBadge = resolved.qualityBadge
                self.activeStreamURL = resolved.url
                self.isDRMStream = resolved.isDRM
                self.trackLoudnessDb = resolved.loudnessDb
                if let resolvedDur = resolved.durationSeconds, resolvedDur > 0 {
                    self.knownDurationSeconds = TimeInterval(resolvedDur)
                    if self.duration <= 0 {
                        self.duration = TimeInterval(resolvedDur)
                    }
                }
                self.syncDSPParameters()

                #if os(iOS)
                if settings.audioPassEnabled, let rate = resolved.sampleRate {
                    try? AVAudioSession.sharedInstance().setPreferredSampleRate(Double(rate))
                }
                #endif

                if resolved.isDRM && resolved.url.scheme == "musickit" {
                    try await playMusicKitDRM(url: resolved.url, resumeAt: resumeAtSeconds, generation: gen)
                } else {
                    let assetURL = try await prepareAssetURL(for: item, resolved: resolved)
                    guard gen == self.loadGeneration else { return }
                    try await startPrimaryDeck(assetURL: assetURL, resumeAt: resumeAtSeconds, generation: gen)
                }

                self.isBuffering = false
                self.isPlaying = true
                self.updateNowPlayingInfo()
            } catch {
                guard gen == self.loadGeneration else { return }
                self.isBuffering = false
                self.isPlaying = false
                self.lastError = error.localizedDescription
            }
        }
    }

    private func resolvePlayableStream(for item: PlaybackItem) async throws -> ModuleStream {
        let cachedURL = await chunkCache.isFullyCached(mediaId: item.id)
            ? await chunkCache.completeFileURL(mediaId: item.id)
            : nil

        let modTrack = ModuleTrack(
            id: item.id,
            title: item.title,
            artist: item.artist,
            durationSeconds: item.durationSeconds,
            isrc: item.isrc,
            localFileURL: item.localFileURL
        )

        return try await router.resolve(
            track: modTrack,
            quality: settings.audioQuality,
            preferMp4OnIOS: settings.preferMp4OnIOS,
            sourceOrder: settings.sourceOrder,
            offlineMode: settings.offlineMode,
            downloadedFileURL: cachedURL
        )
    }

    private func prepareAssetURL(for item: PlaybackItem, resolved: ModuleStream) async throws -> URL {
        if resolved.url.isFileURL {
            return resolved.url
        }

        let mime = resolved.mimeType ?? Self.inferMimeType(codec: resolved.codec, url: resolved.url)
        let descriptor = ProxyStreamDescriptor(
            trackId: item.id,
            url: resolved.url,
            headers: resolved.headers,
            mimeType: mime,
            contentLength: resolved.contentLength
        )

        let routerRef = self.router
        let quality = self.settings.audioQuality
        let preferMp4 = self.settings.preferMp4OnIOS
        let sourceOrder = self.settings.sourceOrder
        let modTrack = ModuleTrack(
            id: item.id,
            title: item.title,
            artist: item.artist,
            durationSeconds: item.durationSeconds,
            isrc: item.isrc,
            localFileURL: nil
        )

        return try await localProxy.registerStream(descriptor) { _ in
            guard let refreshed = try? await routerRef.resolve(
                track: modTrack,
                quality: quality,
                preferMp4OnIOS: preferMp4,
                sourceOrder: sourceOrder,
                offlineMode: false,
                downloadedFileURL: nil
            ), !refreshed.url.isFileURL else {
                return nil
            }
            let refreshedMime = refreshed.mimeType ?? Self.inferMimeType(codec: refreshed.codec, url: refreshed.url)
            return ProxyStreamDescriptor(
                trackId: item.id,
                url: refreshed.url,
                headers: refreshed.headers,
                mimeType: refreshedMime,
                contentLength: refreshed.contentLength
            )
        }
    }

    private func startPrimaryDeck(assetURL: URL, resumeAt: TimeInterval, generation: UInt64) async throws {
        let asset = AVURLAsset(url: assetURL)
        let playerItem = AVPlayerItem(asset: asset)
        if let mix = await AudioProcessingTapBinder.makeAudioMix(for: asset, context: primaryDSPContext) {
            playerItem.audioMix = mix
        }

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        self.primaryPlayer = player

        attachPrimaryObservers(player: player, playerItem: playerItem, generation: generation)

        if resumeAt > 0 {
            await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        if abs(playbackSpeed - 1.0) > 0.01 {
            player.rate = playbackSpeed
        }
    }

    private func attachPrimaryObservers(player: AVPlayer, playerItem: AVPlayerItem, generation: UInt64) {
        primaryEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation, !self.isCrossmixing else { return }
                self.skipNext()
            }
        }

        primaryFailObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                self.handleMidTrackPlaybackFailure(error: err, generation: generation)
            }
        }

        primaryStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let err = item.error
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                self.handleMidTrackPlaybackFailure(error: err, generation: generation)
            }
        }

        primaryTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] cmTime in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                let secs = cmTime.seconds
                if secs.isFinite && secs >= 0 {
                    self.currentTime = secs
                    self.handlePlaybackMilestones(elapsed: secs)
                }

                let reported = playerItem.duration.seconds
                let effective = MP4DurationNormalizer.resolveEffectiveDuration(
                    reported: reported,
                    known: self.knownDurationSeconds
                )
                if effective > 0 {
                    self.duration = effective
                }

                self.evaluateCrossmixTrigger(generation: generation)
            }
        }
    }

    private func handlePlaybackMilestones(elapsed: TimeInterval) {
        guard let item = currentItem else { return }
        if elapsed >= 25 && !playRecordedForGeneration {
            playRecordedForGeneration = true
            try? database.recordPlayEvent(songId: item.id, playTimeMs: Int64(elapsed * 1000))
        }
        let scrobbleTarget = duration > 0 ? min(duration * 0.5, 240.0) : 30.0
        if elapsed >= max(20.0, scrobbleTarget) && !scrobbleFiredForGeneration {
            scrobbleFiredForGeneration = true
            onTrackScrobbleEligible?(item)
        }
    }

    private func handleMidTrackPlaybackFailure(error: Error?, generation: UInt64) {
        guard generation == loadGeneration else { return }
        if !recoveredMidTrackForGeneration, let item = currentItem {
            recoveredMidTrackForGeneration = true
            let resumePos = currentTime
            let failedSrc = activeSourceId.isEmpty ? "youtube" : activeSourceId
            Task {
                await router.markSourceFailed(sourceId: failedSrc, trackId: item.id)
                loadAndPlayCurrent(resumeAtSeconds: resumePos)
            }
            return
        }
        isBuffering = false
        isPlaying = false
        lastError = error?.localizedDescription ?? "Stream playback interrupted."
    }

    private func playMusicKitDRM(url: URL, resumeAt: TimeInterval, generation: UInt64) async throws {
        #if os(iOS) && canImport(MusicKit)
        let trackId = url.lastPathComponent
        var req = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(trackId))
        req.limit = 1
        let resp = try await req.response()
        guard let song = resp.items.first, generation == loadGeneration else {
            throw SourceResolutionError.failedAllSources("Apple Music catalog item not found.")
        }
        let appPlayer = ApplicationMusicPlayer.shared
        appPlayer.queue = [song]
        try await appPlayer.play()
        if resumeAt > 0 {
            appPlayer.playbackTime = resumeAt
        }
        #else
        throw SourceResolutionError.failedAllSources("Apple Music FairPlay playback is iOS-only.")
        #endif
    }

    // MARK: - Dual-Deck Crossmix / MixIt Transition Execution (19 DJ Styles)

    private func evaluateCrossmixTrigger(generation: UInt64) {
        guard isPlaying,
              !settings.audioPassEnabled,
              settings.crossmixMode != .off,
              !isCrossmixing,
              duration > 15,
              let nextIdx = computeNextIndex(),
              crossmixInFlightForIndex != nextIdx else {
            return
        }

        let currentTrack = currentItem
        let nextTrack = queue[nextIdx]
        let customTransition: PlaylistTransition?
        if let playlistId = activePlaylistId, let fromId = currentTrack?.id {
            let saved = (try? database.fetchTransitions(playlistId: playlistId)) ?? []
            customTransition = saved.first { $0.fromSongId == fromId && $0.toSongId == nextTrack.id }
        } else {
            customTransition = nil
        }

        let outProfile = TrackAudioProfile(
            bpm: 120,
            averageRMS: 0.25,
            introSeconds: 0,
            outroStartSeconds: max(0, duration - Double(settings.crossmixDurationMs) / 1000.0)
        )
        let inProfile = TrackAudioProfile(
            bpm: 120,
            averageRMS: 0.25,
            introSeconds: 0,
            outroStartSeconds: Double(max(0, (nextTrack.durationSeconds ?? 180) - 8))
        )

        let plan = CrossmixPlanner.plan(
            from: outProfile,
            to: inProfile,
            durationSeconds: max(1.5, Double(settings.crossmixDurationMs) / 1000.0),
            customTransition: customTransition
        )

        let remaining = duration - currentTime
        let triggerRemaining = customTransition != nil ? max(1.5, duration - plan.outStartSeconds) : plan.durationSeconds
        guard remaining > 0.4, remaining <= triggerRemaining else { return }

        crossmixInFlightForIndex = nextIdx
        startCrossmixTransition(toIndex: nextIdx, plan: plan, custom: customTransition, generation: generation)
    }

    private func startCrossmixTransition(
        toIndex nextIdx: Int,
        plan: CrossmixPlan,
        custom: PlaylistTransition?,
        generation: UInt64
    ) {
        guard queue.indices.contains(nextIdx) else { return }
        let nextItem = queue[nextIdx]
        isCrossmixing = true
        activeCrossmixStyle = plan.style

        Task {
            do {
                let resolved = try await resolvePlayableStream(for: nextItem)
                guard generation == self.loadGeneration, self.isCrossmixing else { return }
                let assetURL = try await prepareAssetURL(for: nextItem, resolved: resolved)
                guard generation == self.loadGeneration, self.isCrossmixing else { return }

                let asset = AVURLAsset(url: assetURL)
                let nextPlayerItem = AVPlayerItem(asset: asset)
                secondaryDSPContext.resetState()
                let initialPair = plan.style.deckParameters(
                    progress: 0,
                    bpm: plan.bpm,
                    outVoiceLevel: custom?.outVoiceLevel ?? 1.0,
                    outBassLevel: custom?.outBassLevel ?? 1.0,
                    inVoiceLevel: custom?.inVoiceLevel ?? 1.0,
                    inBassLevel: custom?.inBassLevel ?? 1.0
                )
                secondaryDSPContext.updateFX(mergeWithBaseline(initialPair.incoming), bypassAll: false)

                if let mix = await AudioProcessingTapBinder.makeAudioMix(for: asset, context: secondaryDSPContext) {
                    nextPlayerItem.audioMix = mix
                }

                let incomingPlayer = AVPlayer(playerItem: nextPlayerItem)
                self.secondaryPlayer = incomingPlayer
                if plan.inStartSeconds > 0 {
                    await incomingPlayer.seek(to: CMTime(seconds: plan.inStartSeconds, preferredTimescale: 600))
                }
                incomingPlayer.play()

                let startedAt = Date()
                let totalDur = max(1.0, plan.durationSeconds)

                crossmixTimer?.invalidate()
                crossmixTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.loadGeneration == generation, self.isCrossmixing else { return }
                        let t = Float(min(1.0, Date().timeIntervalSince(startedAt) / totalDur))
                        let curves = plan.style.deckParameters(
                            progress: t,
                            bpm: plan.bpm,
                            outVoiceLevel: custom?.outVoiceLevel ?? 1.0,
                            outBassLevel: custom?.outBassLevel ?? 1.0,
                            inVoiceLevel: custom?.inVoiceLevel ?? 1.0,
                            inBassLevel: custom?.inBassLevel ?? 1.0
                        )
                        self.primaryDSPContext.updateFX(self.mergeWithBaseline(curves.outgoing), bypassAll: false)
                        self.secondaryDSPContext.updateFX(self.mergeWithBaseline(curves.incoming), bypassAll: false)

                        if t >= 1.0 {
                            self.finishCrossmixSwap(
                                newIndex: nextIdx,
                                incomingPlayer: incomingPlayer,
                                incomingItem: nextPlayerItem,
                                resolved: resolved
                            )
                        }
                    }
                }
            } catch {
                self.cancelActiveCrossmix()
            }
        }
    }

    private func finishCrossmixSwap(
        newIndex: Int,
        incomingPlayer: AVPlayer,
        incomingItem: AVPlayerItem,
        resolved: ModuleStream
    ) {
        crossmixTimer?.invalidate()
        crossmixTimer = nil
        isCrossmixing = false
        crossmixInFlightForIndex = nil

        // Tear down old primary player and promote secondary deck to primary seamlessly.
        tearDownPrimaryObservers()
        primaryPlayer?.pause()
        primaryPlayer = incomingPlayer
        secondaryPlayer = nil

        let swappedContext = secondaryDSPContext
        secondaryDSPContext = primaryDSPContext
        primaryDSPContext = swappedContext

        loadGeneration &+= 1
        let gen = loadGeneration
        currentIndex = newIndex
        playRecordedForGeneration = false
        scrobbleFiredForGeneration = false
        recoveredMidTrackForGeneration = false
        activeSourceId = resolved.sourceId
        activeSourceLabel = resolved.sourceLabel
        activeQualityBadge = resolved.qualityBadge
        activeStreamURL = resolved.url
        isDRMStream = resolved.isDRM
        trackLoudnessDb = resolved.loudnessDb
        knownDurationSeconds = (resolved.durationSeconds ?? currentItem?.durationSeconds).map(TimeInterval.init)
        duration = knownDurationSeconds ?? 0

        syncDSPParameters()
        attachPrimaryObservers(player: incomingPlayer, playerItem: incomingItem, generation: gen)
        if let item = currentItem {
            fetchAndCacheArtwork(for: item)
        }
        maybeAppendRadioContinuation()
        updateNowPlayingInfo()
    }

    private func mergeWithBaseline(_ curve: MochyFXParameters) -> MochyFXParameters {
        var merged = makeBaselineFXParameters()
        merged.crossmixGain = curve.crossmixGain
        merged.lowCutHz = curve.lowCutHz
        merged.highCutHz = curve.highCutHz
        merged.bassCut = curve.bassCut
        merged.vocalCenterCut = curve.vocalCenterCut
        merged.sideCut = curve.sideCut
        merged.echoMix = curve.echoMix
        merged.echoDelayMs = curve.echoDelayMs
        merged.flangerMix = curve.flangerMix
        merged.crushMix = curve.crushMix
        merged.reverbMix = max(merged.reverbMix, curve.reverbMix)
        merged.warmth = max(merged.warmth, curve.warmth)
        merged.orbitRateHz = max(merged.orbitRateHz, curve.orbitRateHz)
        return merged
    }

    private func cancelActiveCrossmix() {
        crossmixTimer?.invalidate()
        crossmixTimer = nil
        if isCrossmixing {
            isCrossmixing = false
            secondaryPlayer?.pause()
            secondaryPlayer = nil
            syncDSPParameters()
        }
    }

    // MARK: - Radio Continuation & Deck Cleanup

    private func computeNextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if shuffleEnabled && queue.count > 1 {
            var next = Int.random(in: 0..<queue.count)
            if next == currentIndex { next = (currentIndex + 1) % queue.count }
            return next
        }
        if currentIndex + 1 < queue.count {
            return currentIndex + 1
        }
        if repeatMode == .all {
            return 0
        }
        return nil
    }

    private func maybeAppendRadioContinuation() {
        guard settings.infiniteQueueEnabled,
              !settings.offlineMode,
              !isFetchingRadio,
              let seed = currentItem,
              seed.localFileURL == nil,
              currentIndex >= queue.count - 2,
              let continuation = onRequestRadioContinuation else {
            return
        }
        isFetchingRadio = true
        let seedId = seed.id
        Task {
            defer { self.isFetchingRadio = false }
            let fetched = await continuation(seedId)
            let existingIds = Set(self.queue.map(\.id))
            let unique = fetched.filter { !existingIds.contains($0.id) }
            if !unique.isEmpty {
                self.queue.append(contentsOf: unique)
            }
        }
    }

    private func tearDownPrimaryObservers() {
        if let token = primaryTimeObserver, let p = primaryPlayer {
            p.removeTimeObserver(token)
            primaryTimeObserver = nil
        }
        if let endObs = primaryEndObserver {
            NotificationCenter.default.removeObserver(endObs)
            primaryEndObserver = nil
        }
        if let failObs = primaryFailObserver {
            NotificationCenter.default.removeObserver(failObs)
            primaryFailObserver = nil
        }
        primaryStatusObservation?.invalidate()
        primaryStatusObservation = nil
    }

    private func stopAllDecks() {
        cancelActiveCrossmix()
        tearDownPrimaryObservers()
        primaryPlayer?.pause()
        primaryPlayer = nil
        secondaryPlayer?.pause()
        secondaryPlayer = nil
    }

    // MARK: - Real-Time FFT Spectrum Polling & CoreHaptics

    private func startSpectrumPollingTimer() {
        spectrumTimer?.invalidate()
        spectrumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying && !self.isDRMStream {
                    let snap = self.primaryDSPContext.spectrumSnapshot()
                    self.spectrumBins = snap.bins
                    if self.settings.dspStageEnabled && !self.settings.audioPassEnabled {
                        self.stageLevels = self.primaryDSPContext.stageLevels()
                    }
                    self.triggerBassHapticIfNeeded(energy: snap.bassEnergy)
                } else if self.spectrumBins.contains(where: { $0 > 0.01 }) {
                    self.spectrumBins = self.spectrumBins.map { $0 * 0.72 }
                }
            }
        }
    }

    private func triggerBassHapticIfNeeded(energy: Float) {
        #if os(iOS) && canImport(CoreHaptics)
        guard settings.hapticsEnabled, energy > 0.65 else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastHapticBeatTime > 0.16 else { return }
        lastHapticBeatTime = now
        if hapticEngine == nil {
            hapticEngine = try? CHHapticEngine()
            try? hapticEngine?.start()
        }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1.0, energy))
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.32)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? hapticEngine?.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
        #endif
    }

    // MARK: - AVAudioSession Interruptions, Route Changes & Lock Screen Artwork

    private func setupAudioSessionAndRemoteCommands() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)

        let intObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.wasPlayingBeforeInterruption = self.isPlaying
                    if self.isPlaying { self.pause() }
                case .ended:
                    if options.contains(.shouldResume) && self.wasPlayingBeforeInterruption {
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.resume()
                    }
                    self.wasPlayingBeforeInterruption = false
                @unknown default:
                    break
                }
            }
        }

        let routeObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
            if reason == .oldDeviceUnavailable {
                Task { @MainActor in self?.pause() }
            }
        }

        let resetObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.syncDSPParameters()
            }
        }
        sessionObservers = [intObs, routeObs, resetObs]
        #endif

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipNext() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipPrevious() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: posEvent.positionTime) }
                return .success
            }
            return .commandFailed
        }
        commandCenter.changeShuffleModeCommand.addTarget { [weak self] event in
            if let shuf = event as? MPChangeShuffleModeCommandEvent {
                Task { @MainActor in self?.shuffleEnabled = (shuf.shuffleType != .off) }
                return .success
            }
            return .commandFailed
        }
        commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            if let rep = event as? MPChangeRepeatModeCommandEvent {
                Task { @MainActor in
                    switch rep.repeatType {
                    case .off: self?.repeatMode = .off
                    case .one: self?.repeatMode = .one
                    case .all: self?.repeatMode = .all
                    @unknown default: self?.repeatMode = .off
                    }
                }
                return .success
            }
            return .commandFailed
        }
    }

    private func fetchAndCacheArtwork(for item: PlaybackItem) {
        guard cachedArtworkSongId != item.id else { return }
        cachedArtworkSongId = item.id
        cachedArtworkData = nil
        guard let urlStr = item.thumbnailURL, let url = URL(string: urlStr) else { return }
        let targetId = item.id
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  self.currentItem?.id == targetId else { return }
            self.cachedArtworkData = data
            self.updateNowPlayingInfo()
        }
    }

    private func updateNowPlayingInfo() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let album = item.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        #if os(iOS) && canImport(UIKit)
        if let data = cachedArtworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    nonisolated private static func inferMimeType(codec: String, url: URL) -> String {
        let c = codec.lowercased()
        if c.contains("flac") { return "audio/flac" }
        if c.contains("mp3") { return "audio/mpeg" }
        if c.contains("wav") { return "audio/wav" }
        if url.pathExtension.lowercased() == "mp4" { return "video/mp4" }
        return "audio/mp4"
    }
}
