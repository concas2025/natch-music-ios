import Accelerate
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
            localFileURL: song.localUri.flatMap(URL.init(string:))
        )
    }
}

/// Dual-Deck AVAudioEngine + Remote AVPlayer Audio Controller matching Mochy Music's playback service.
@MainActor
@Observable
public final class MochyAudioPlayer {
    public private(set) var queue: [PlaybackItem] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var activeSourceLabel: String = ""
    public private(set) var activeQualityBadge: String = ""
    public private(set) var activeStreamURL: URL?
    public private(set) var isDRMStream: Bool = false
    public private(set) var spectrumBins: [Float] = Array(repeating: 0, count: 32)
    public private(set) var activeCrossmixStyle: CrossmixStyle = .silkBlend
    public private(set) var lastError: String?

    public var shuffleEnabled: Bool = false
    public var repeatMode: RepeatMode = .off
    public var eqGainsDb: [Float] = Array(repeating: 0, count: 10) {
        didSet { syncDSPParameters() }
    }
    public var stageParams = StageParameters() {
        didSet { stageEngine.update(stageParams) }
    }

    public var currentItem: PlaybackItem? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    private let settings: AppSettings
    private let router: SourceModulesRouter
    private let database: MochyDatabase
    private let chunkCache = ChunkRangeCache()

    private let engine = AVAudioEngine()
    private let deckA = AVAudioPlayerNode()
    private let deckB = AVAudioPlayerNode()
    private let pitchNode = AVAudioUnitTimePitch()
    private let fxEngine = MochyFXEngine(sampleRate: 48_000)
    private let stageEngine = MochyStageEngine(sampleRate: 48_000, channels: 2)

    private var remotePlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var progressTimer: Timer?
    private var loadGeneration: UInt64 = 0
    private var playRecordedForGeneration = false
    private var usingAudioEngineDeck = false

    #if os(iOS) && canImport(CoreHaptics)
    private var hapticEngine: CHHapticEngine?
    private var lastHapticBeatTime: TimeInterval = 0
    #endif

    public init(settings: AppSettings, router: SourceModulesRouter, database: MochyDatabase) {
        self.settings = settings
        self.router = router
        self.database = database
        setupAudioSessionAndRemoteCommands()
        setupAudioEngineGraph()
    }

    public func playQueue(_ items: [PlaybackItem], startIndex: Int = 0) {
        guard !items.isEmpty else { return }
        self.queue = items
        self.currentIndex = max(0, min(startIndex, items.count - 1))
        loadAndPlayCurrent()
    }

    public func appendToQueue(_ item: PlaybackItem) {
        queue.append(item)
        if queue.count == 1 {
            currentIndex = 0
            loadAndPlayCurrent()
        }
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
        if usingAudioEngineDeck {
            deckA.pause()
        } else {
            remotePlayer?.pause()
        }
        updateNowPlayingInfo()
    }

    public func resume() {
        guard currentItem != nil else { return }
        isPlaying = true
        if usingAudioEngineDeck {
            if !engine.isRunning { try? engine.start() }
            deckA.play()
        } else {
            remotePlayer?.play()
        }
        updateNowPlayingInfo()
    }

    public func skipNext() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            seek(to: 0)
            return
        }
        if shuffleEnabled && queue.count > 1 {
            var next = Int.random(in: 0..<queue.count)
            if next == currentIndex { next = (currentIndex + 1) % queue.count }
            currentIndex = next
        } else if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            pause()
            return
        }
        loadAndPlayCurrent()
    }

    public func skipPrevious() {
        if currentTime > 4.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
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
        if !usingAudioEngineDeck, let remotePlayer {
            remotePlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
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

    public func syncDSPParameters() {
        var params = MochyFXParameters()
        params.enabled = !settings.audioPassEnabled
        params.eqGainsDb = settings.dspEqEnabled ? eqGainsDb : Array(repeating: 0, count: 10)
        params.orbitRateHz = settings.dspOrbitEnabled ? 0.18 : 0.0
        fxEngine.update(params)

        stageParams.enabled = !settings.audioPassEnabled && settings.dspStageEnabled
        stageEngine.update(stageParams)
    }

    // MARK: - Just-In-Time Track Preparation (Generation Guarded)

    private func loadAndPlayCurrent(resumeAtSeconds: TimeInterval = 0) {
        guard let item = currentItem else { return }
        loadGeneration &+= 1
        let gen = loadGeneration
        playRecordedForGeneration = false
        lastError = nil
        isBuffering = true
        currentTime = resumeAtSeconds
        duration = TimeInterval(item.durationSeconds ?? 0)
        stopActivePlaybackNodes()

        Task {
            do {
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

                let resolved = try await router.resolve(
                    track: modTrack,
                    quality: settings.audioQuality,
                    preferMp4OnIOS: settings.preferMp4OnIOS,
                    sourceOrder: settings.sourceOrder,
                    offlineMode: settings.offlineMode,
                    downloadedFileURL: cachedURL
                )

                guard gen == self.loadGeneration else { return }

                self.activeSourceLabel = resolved.sourceLabel
                self.activeQualityBadge = resolved.qualityBadge
                self.activeStreamURL = resolved.url
                self.isDRMStream = resolved.isDRM

                #if os(iOS)
                if settings.audioPassEnabled, let rate = resolved.sampleRate {
                    try? AVAudioSession.sharedInstance().setPreferredSampleRate(Double(rate))
                }
                #endif

                if resolved.url.isFileURL {
                    try playLocalAudioFile(url: resolved.url, generation: gen)
                } else {
                    playRemoteAVPlayer(stream: resolved, resumeAt: resumeAtSeconds, generation: gen)
                    Task.detached { [weak self] in
                        await self?.chunkCache.prefetchFirstChunk(
                            mediaId: item.id,
                            url: resolved.url,
                            headers: resolved.headers
                        )
                    }
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

    private func playLocalAudioFile(url: URL, generation: UInt64) throws {
        usingAudioEngineDeck = true
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        duration = Double(file.length) / format.sampleRate
        if !engine.isRunning { try engine.start() }

        deckA.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation, self.isPlaying else { return }
                self.skipNext()
            }
        }
        deckA.play()
        startLocalProgressTimer(generation: generation)
    }

    private func playRemoteAVPlayer(stream: ModuleStream, resumeAt: TimeInterval, generation: UInt64) {
        usingAudioEngineDeck = false
        let asset: AVURLAsset
        if stream.headers.isEmpty {
            asset = AVURLAsset(url: stream.url)
        } else {
            asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        }
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        self.remotePlayer = player

        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                self.skipNext()
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] cmTime in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                let secs = cmTime.seconds
                if secs.isFinite {
                    self.currentTime = secs
                    if secs >= 25 && !self.playRecordedForGeneration, let item = self.currentItem {
                        self.playRecordedForGeneration = true
                        try? self.database.recordPlayEvent(songId: item.id, playTimeMs: Int64(secs * 1000))
                    }
                }
                let total = playerItem.duration.seconds
                if total.isFinite && total > 0 {
                    self.duration = total
                }
                if self.isPlaying {
                    self.updateSimulatedSpectrumIfRemote()
                }
            }
        }

        player.play()
    }

    private func startLocalProgressTimer(generation: UInt64) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation, self.isPlaying else { return }
                self.currentTime = min(self.duration, self.currentTime + 0.25)
                if self.currentTime >= 25 && !self.playRecordedForGeneration, let item = self.currentItem {
                    self.playRecordedForGeneration = true
                    try? self.database.recordPlayEvent(songId: item.id, playTimeMs: Int64(self.currentTime * 1000))
                }
            }
        }
    }

    private func stopActivePlaybackNodes() {
        deckA.stop()
        deckB.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        if let token = timeObserverToken, let rp = remotePlayer {
            rp.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endObs = endObserver {
            NotificationCenter.default.removeObserver(endObs)
            endObserver = nil
        }
        remotePlayer?.pause()
        remotePlayer = nil
    }

    // MARK: - AVAudioEngine Setup & DSP Tap

    private func setupAudioEngineGraph() {
        engine.attach(deckA)
        engine.attach(deckB)
        engine.attach(pitchNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.connect(deckA, to: pitchNode, format: format)
        engine.connect(deckB, to: engine.mainMixerNode, format: format)
        engine.connect(pitchNode, to: engine.mainMixerNode, format: format)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            if frames > 0 && buffer.format.channelCount >= 2 {
                self.fxEngine.process(left: channelData[0], right: channelData[1], frames: frames)
                if !self.settings.audioPassEnabled && self.settings.dspStageEnabled {
                    self.stageEngine.process(left: channelData[0], right: channelData[1], frames: frames)
                }
                let bins = Self.computeSpectrumBins(samples: channelData[0], count: frames)
                Task { @MainActor in
                    self.spectrumBins = bins
                    self.triggerBassHapticIfNeeded(energy: bins.prefix(4).reduce(0, +) / 4.0)
                }
            }
        }
        syncDSPParameters()
    }

    private static func computeSpectrumBins(samples: UnsafePointer<Float>, count: Int) -> [Float] {
        let binCount = 32
        var bins = [Float](repeating: 0, count: binCount)
        let step = max(1, count / binCount)
        for b in 0..<binCount {
            var peak: Float = 0
            let start = b * step
            let end = min(count, start + step)
            for i in start..<end {
                peak = max(peak, abs(samples[i]))
            }
            bins[b] = min(1.0, peak * 1.8)
        }
        return bins
    }

    private func updateSimulatedSpectrumIfRemote() {
        // Light rhythmic envelope fallback when AVPlayer bypasses engine PCM tap
        let t = currentTime
        spectrumBins = (0..<32).map { idx in
            let wave = abs(sin(t * 4.2 + Double(idx) * 0.45)) * 0.65 + 0.15
            return Float(wave)
        }
    }

    private func triggerBassHapticIfNeeded(energy: Float) {
        #if os(iOS) && canImport(CoreHaptics)
        guard settings.hapticsEnabled, energy > 0.68 else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastHapticBeatTime > 0.18 else { return }
        lastHapticBeatTime = now
        if hapticEngine == nil {
            hapticEngine = try? CHHapticEngine()
            try? hapticEngine?.start()
        }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1.0, energy))
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? hapticEngine?.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
        #endif
    }

    private func setupAudioSessionAndRemoteCommands() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let album = item.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
