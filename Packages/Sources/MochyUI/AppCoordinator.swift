import AVFoundation
import Foundation
import MochyAudio
import MochyCore
import MochyDatabase
import MochyDSP
import MochyInnerTube
import MochyLyrics
import MochyModules
import MochySync
import Observation
import SwiftUI

public enum RootNavTab: String, CaseIterable, Sendable {
    case home
    case search
    case library
    case settings

    public var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }

    public var inactiveSystemImage: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

public struct LiveActivitySnapshot: Sendable, Equatable {
    public let songId: String
    public let title: String
    public let artist: String
    public let activeLyricLine: String
    public let isPlaying: Bool
    public let progress: Double
}

@MainActor
@Observable
public final class AppCoordinator {
    public var settings: AppSettings
    public let database: MochyDatabase
    public let innerTube: InnerTubeClient
    public let resolver: YTPlayerResolver
    public let monochromeModule: MonochromeModule
    public let jioSaavnModule: JioSaavnModule
    public let router: SourceModulesRouter
    public var player: MochyAudioPlayer
    public let lyricsHelper: LyricsHelper
    public let lyricsTranslator: LyricsTranslator
    public let syncManager: YouTubeSyncManager
    public let playlistImporter: PlaylistImportService
    public let cloudBackup: CloudBackupManager
    public let shazam: ShazamRecognizer
    public let linkService: MochyLinkService
    public let scrobbler: LastFmScrobbler
    public let discord: DiscordPresenceClient

    /// Optional callback supplied by `MochyApp` to drive iOS `ActivityKit` Live Activities cleanly from the App target.
    public var onLiveActivityUpdate: ((LiveActivitySnapshot?) -> Void)?

    // Navigation & Player Sheet Motion
    public var selectedTab: RootNavTab = .home
    public var isPlayerExpanded: Bool = false
    public var playerDragProgress: CGFloat = 0
    public var searchFocusTrigger: Int = 0
    public var scrollToTopTrigger: Int = 0

    // Catalog, Library & Lyrics State
    public var homeSections: [YTHomeSection] = []
    public var isLoadingHome = false
    public var searchQuery: String = ""
    public var searchSuggestions: [String] = []
    public var searchResults: [YTTrackItem] = []
    public var isSearching = false
    public var recentSearches: [String] = []

    public var librarySongs: [SongEntity] = []
    public var libraryPlaylists: [PlaylistEntity] = []
    public var libraryAlbums: [AlbumEntity] = []
    public var libraryArtists: [ArtistEntity] = []
    public var recentlyPlayedSongs: [SongEntity] = []
    public var mostPlayedSongs: [SongEntity] = []
    public var importedPlaylistIds: Set<String> = []
    public var songArtistsById: [String: String] = [:]
    public var downloadedSongIds: Set<String> = []
    public var speedDialItems: [SpeedDialItem] = []
    public var songEditsById: [String: SongEdit] = [:]

    public var currentLyrics: LyricsDocument?
    public var currentLyricsOffsetMs: Int = 0
    public var isLoadingLyrics = false
    public var paletteColors: [Color] = [Color(white: 0.24), Color(white: 0.15), Color(white: 0.08), .black]
    public var currentModuleSkin: ModuleSkinManifest = .defaultSkin
    public var videoStreamOptions: [YTVideoStreamOption] = []

    // Playlist Import & Sync Status
    public var isImportingPlaylist = false
    public var importProgress: ImportProgressUpdate?
    public var importStatusMessage: String?
    public var isSignedInToYouTube: Bool = false
    public var syncStatusMessage: String?
    public var canUndoLastSync: Bool = false
    public var playingFromLabel: String = "Recommendations"
    public var dislikedSongIds: Set<String> = []
    public var menuToastMessage: String?

    public var activeProgress: CGFloat {
        isPlayerExpanded ? max(0, min(1, 1 - playerDragProgress)) : max(0, min(1, playerDragProgress))
    }

    private var lastLoadedTrackId: String?

    public init(
        settings: AppSettings,
        database: MochyDatabase
    ) {
        self.settings = settings
        self.database = database

        let cookie = SecretVault.get(.ytmCookie)
        let visitor = SecretVault.get(.ytmVisitorData)
        let dataSync = SecretVault.get(.ytmDataSyncId)
        let yt = InnerTubeClient(
            locale: YouTubeLocale(gl: settings.countryCode, hl: settings.languageCode),
            cookie: cookie,
            visitorData: visitor,
            dataSyncId: dataSync
        )
        self.innerTube = yt
        self.resolver = YTPlayerResolver(innerTube: yt)
        self.monochromeModule = MonochromeModule()
        self.jioSaavnModule = JioSaavnModule()
        self.router = SourceModulesRouter(
            youtubeResolver: self.resolver,
            modules: [self.monochromeModule, self.jioSaavnModule, AppleMusicModule()]
        )
        self.player = MochyAudioPlayer(settings: settings, router: self.router, database: database)
        self.lyricsHelper = LyricsHelper(lastResortProvider: YouTubeCaptionsLyricsProvider(innerTube: yt))
        self.lyricsTranslator = LyricsTranslator()
        self.syncManager = YouTubeSyncManager(innerTube: yt, database: database)
        self.playlistImporter = PlaylistImportService(innerTube: yt, database: database)
        self.cloudBackup = CloudBackupManager(database: database)
        self.shazam = ShazamRecognizer(database: database)
        self.linkService = MochyLinkService()
        self.scrobbler = LastFmScrobbler()
        self.discord = DiscordPresenceClient()
        self.isSignedInToYouTube = !(cookie?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        wireRuntimeCallbacks()
        refreshLocalLibrary()

        Task {
            await syncRegisteredModulesFromSettings()
            await refreshDownloadedState()
            await ensureGuestVisitorData()
        }
    }

    private func wireRuntimeCallbacks() {
        // Infinite Radio Up Next continuation
        player.onRequestRadioContinuation = { [weak self] seedVideoId in
            guard let self else { return [] }
            let nextTracks = (try? await self.innerTube.nextQueue(videoId: seedVideoId)) ?? []
            return nextTracks.map(PlaybackItem.init(ytTrack:))
        }

        // Last.fm Scrobble trigger at 50% / 240s milestone
        player.onTrackScrobbleEligible = { [weak self] item in
            guard let self else { return }
            Task {
                await self.scrobbler.enqueueScrobble(artist: item.artist, track: item.title)
                await self.scrobbler.flushStoredCredentials()
            }
        }

        // Mochy Link LAN remote control command execution
        linkService.onCommandReceived = { [weak self] cmd in
            guard let self else { return }
            switch cmd.action {
            case "play": self.player.resume()
            case "pause": self.player.pause()
            case "toggle": self.player.togglePlayPause()
            case "next": self.player.skipNext()
            case "previous", "prev": self.player.skipPrevious()
            case "seek":
                if let secs = cmd.value { self.player.seek(to: secs) }
            default:
                break
            }
        }
    }

    public func ensureGuestVisitorData() async {
        if let visitor = await innerTube.ensureGuestVisitorData(), !visitor.isEmpty {
            try? SecretVault.set(visitor, for: .ytmVisitorData)
        }
    }

    public func syncRegisteredModulesFromSettings() async {
        await monochromeModule.setCustomServers(settings.customMonochromeServers)
        for rawURL in settings.webModuleURLs {
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), ModuleUrlGuard.isAllowedPublicURL(url) else { continue }
            let modId = "web_\(url.host ?? "custom")"
            let name = (try? await WebStreamModule.loadManifest(from: url)?.name) ?? (url.host ?? "Web Module")
            await router.registerModule(WebStreamModule(id: modId, displayName: name, baseURL: url))
        }
    }

    public func onSelectTab(_ tab: RootNavTab) {
        if tab == selectedTab {
            if tab == .search {
                searchFocusTrigger += 1
            } else {
                scrollToTopTrigger += 1
            }
        } else {
            selectedTab = tab
        }
    }

    public func artistDisplay(for song: SongEntity) -> String {
        if let custom = songEditsById[song.id]?.artists, !custom.isEmpty {
            return custom
        }
        if let mapped = songArtistsById[song.id], !mapped.isEmpty {
            return mapped
        }
        if let album = song.albumName, !album.isEmpty {
            return album
        }
        return "Unknown Artist"
    }

    public func refreshLocalLibrary() {
        librarySongs = (try? database.fetchAllSongs()) ?? []
        libraryPlaylists = (try? database.fetchPlaylists()) ?? []
        libraryAlbums = (try? database.fetchAlbums()) ?? []
        libraryArtists = (try? database.fetchArtists()) ?? []
        importedPlaylistIds = (try? database.fetchImportedPlaylistIds()) ?? []
        speedDialItems = (try? database.fetchSpeedDialItems()) ?? []
        recentSearches = (try? database.recentSearches()) ?? []
        let edits = (try? database.fetchAllSongEdits()) ?? []
        songEditsById = Dictionary(uniqueKeysWithValues: edits.map { ($0.songId, $0) })

        let artistNamesById = Dictionary(uniqueKeysWithValues: libraryArtists.map { ($0.id, $0.name) })
        let artistMaps = ((try? database.fetchAllSongArtistMaps()) ?? []).sorted { $0.position < $1.position }
        var groupedArtists: [String: [String]] = [:]
        for map in artistMaps {
            if let name = artistNamesById[map.artistId], !name.isEmpty {
                groupedArtists[map.songId, default: []].append(name)
            }
        }
        songArtistsById = groupedArtists.mapValues { $0.joined(separator: ", ") }

        let songsById = Dictionary(uniqueKeysWithValues: librarySongs.map { ($0.id, $0) })
        var seenRecent = Set<String>()
        var recentList: [SongEntity] = []
        let events = (try? database.fetchRecentEvents(limit: 40)) ?? []
        for ev in events {
            if seenRecent.insert(ev.songId).inserted, let s = songsById[ev.songId] {
                recentList.append(s)
            }
        }
        let sortedByTime = librarySongs.sorted {
            ($0.dateModified ?? $0.inLibrary ?? 0) > ($1.dateModified ?? $1.inLibrary ?? 0)
        }
        for s in sortedByTime where recentList.count < 24 {
            if seenRecent.insert(s.id).inserted {
                recentList.append(s)
            }
        }
        recentlyPlayedSongs = Array(recentList.prefix(24))
        mostPlayedSongs = ((try? database.fetchTopSongs(limit: 24)) ?? []).filter { $0.totalPlayTime > 0 }
    }

    public func refreshDownloadedState() async {
        downloadedSongIds = await player.chunkCache.downloadedMediaIds()
    }

    public func isLiked(songId: String?) -> Bool {
        guard let songId else { return false }
        return librarySongs.first(where: { $0.id == songId })?.liked ?? false
    }

    public func activeLyricLineText() -> String {
        guard let doc = currentLyrics, !doc.lines.isEmpty else { return "" }
        let nowMs = Int(player.currentTime * 1000) + currentLyricsOffsetMs
        if doc.isSynced {
            return doc.lines.last(where: { $0.startMs <= nowMs })?.text ?? doc.lines.first?.text ?? ""
        }
        return doc.lines.first?.text ?? ""
    }

    public func publishLiveActivityState() {
        guard let item = player.currentItem else {
            onLiveActivityUpdate?(nil)
            return
        }
        let pct = player.duration > 0 ? min(1.0, max(0.0, player.currentTime / player.duration)) : 0
        onLiveActivityUpdate?(
            LiveActivitySnapshot(
                songId: item.id,
                title: item.title,
                artist: item.artist,
                activeLyricLine: activeLyricLineText(),
                isPlaying: player.isPlaying,
                progress: pct
            )
        )
    }

    // MARK: - Catalog & Search

    public func loadHomeFeedIfNeeded() async {
        guard homeSections.isEmpty, !isLoadingHome else { return }
        await reloadHomeFeed()
    }

    public func updateSuggestions(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchSuggestions = []
            return
        }
        if let sugg = try? await innerTube.searchSuggestions(query: trimmed) {
            searchSuggestions = sugg
        }
    }

    public func runSearch(query: String? = nil) async {
        let q = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchQuery = q
        isSearching = true
        defer { isSearching = false }
        try? database.recordSearch(query: q)
        refreshLocalLibrary()

        if let tracks = try? await innerTube.searchTracks(query: q) {
            searchResults = tracks
        }
    }

    public func playTrack(_ track: YTTrackItem, queueContext: [YTTrackItem]? = nil, sourceLabel: String? = nil) {
        if let sourceLabel, !sourceLabel.isEmpty {
            playingFromLabel = sourceLabel
        }
        let items = (queueContext ?? [track]).map(PlaybackItem.init(ytTrack:))
        let startIdx = queueContext?.firstIndex(where: { $0.id == track.id }) ?? 0
        player.playQueue(items, startIndex: startIdx)
        saveTrackMetadataToDB(track)
        onTrackChanged()
    }

    public func playLocalSong(_ song: SongEntity, allSongs: [SongEntity], playlistId: String? = nil) {
        let items = allSongs.map { s -> PlaybackItem in
            let edit = songEditsById[s.id]
            let artists = (try? database.fetchArtistsForSong(songId: s.id).map(\.name)) ?? []
            var item = PlaybackItem(song: s, artistNames: artists)
            if let edit {
                item = PlaybackItem(
                    id: item.id,
                    title: edit.title ?? item.title,
                    artist: edit.artists ?? item.artist,
                    album: edit.album ?? item.album,
                    durationSeconds: item.durationSeconds,
                    thumbnailURL: edit.cover ?? item.thumbnailURL,
                    localFileURL: item.localFileURL
                )
            }
            return item
        }
        let startIdx = allSongs.firstIndex(where: { $0.id == song.id }) ?? 0
        player.playQueue(items, startIndex: startIdx, playlistId: playlistId)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var touched = song
        touched.dateModified = nowMs
        if touched.inLibrary == nil { touched.inLibrary = nowMs }
        try? database.upsertSong(touched)
        refreshLocalLibrary()
        onTrackChanged()
    }

    public func playShazamMatch(_ entry: RecognitionHistoryEntity) async {
        let query = "\(entry.title) \(entry.artist)"
        if let hits = try? await innerTube.searchTracks(query: query), let first = hits.first {
            playTrack(first, queueContext: hits)
        }
    }

    // MARK: - Track Lifecycle, Lossless Lyrics Cache & AutoSync

    public func onTrackChanged() {
        guard let item = player.currentItem, item.id != lastLoadedTrackId else { return }
        lastLoadedTrackId = item.id
        currentLyrics = nil
        videoStreamOptions = []
        currentLyricsOffsetMs = (try? database.fetchSong(id: item.id)?.lyricsOffset) ?? 0

        Task {
            await loadLyricsForCurrentTrack()
            await updatePalette(from: item.thumbnailURL)
            await scrobbler.updateNowPlaying(artist: item.artist, track: item.title)
            await discord.updateListeningPresence(title: item.title, artist: item.artist, durationSeconds: item.durationSeconds)
            await refreshDownloadedState()
            publishLiveActivityState()
        }
    }

    public func loadLyricsForCurrentTrack(forceRefresh: Bool = false) async {
        guard let item = player.currentItem else { return }
        isLoadingLyrics = true
        defer { isLoadingLyrics = false }

        if !forceRefresh,
           let cached = try? database.fetchLyrics(id: item.id),
           var parsed = LyricsDocument.decodeCachePayload(cached.lyrics, provider: cached.provider) {
            if settings.lyricsRomanize && parsed.lines.allSatisfy({ $0.romanized == nil }) {
                parsed = LyricsRomanizer.romanizedDocument(parsed)
            }
            if settings.lyricsTranslate && parsed.lines.allSatisfy({ $0.translated == nil }) {
                parsed = await lyricsTranslator.translate(
                    document: parsed,
                    targetLanguage: settings.lyricsTranslationLanguage
                )
                persistLyricsDocument(parsed, songId: item.id)
            }
            currentLyrics = parsed
            publishLiveActivityState()
            return
        }

        let query = LyricsQuery(
            videoId: item.id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            durationSeconds: item.durationSeconds ?? 0,
            isrc: item.isrc,
            localFileURL: item.localFileURL
        )
        if var doc = await lyricsHelper.fetchLyrics(query: query, orderOverride: settings.lyricsOrderOverride) {
            if settings.lyricsRomanize {
                doc = LyricsRomanizer.romanizedDocument(doc)
            }
            if settings.lyricsTranslate {
                doc = await lyricsTranslator.translate(
                    document: doc,
                    targetLanguage: settings.lyricsTranslationLanguage
                )
            }
            currentLyrics = doc
            persistLyricsDocument(doc, songId: item.id)
            publishLiveActivityState()
        }
    }

    private func persistLyricsDocument(_ doc: LyricsDocument, songId: String) {
        let translatedJoined = doc.lines.compactMap(\.translated).joined(separator: "\n")
        try? database.upsertLyrics(
            LyricsEntity(
                id: songId,
                lyrics: doc.encodeCachePayload(),
                provider: doc.sourceProvider,
                translatedLyrics: translatedJoined,
                translationLanguage: translatedJoined.isEmpty ? "" : settings.lyricsTranslationLanguage,
                translationMode: translatedJoined.isEmpty ? "" : "auto"
            )
        )
    }

    public func updateCurrentLyricsOffset(_ newOffsetMs: Int) {
        let clamped = max(-5000, min(5000, newOffsetMs))
        currentLyricsOffsetMs = clamped
        if let id = player.currentItem?.id {
            try? database.updateLyricsOffset(songId: id, offsetMs: clamped)
        }
    }

    /// Runs `LyricsAutoSync.estimateOffsetMs` against the cached or local PCM audio of the active track.
    public func autoSyncCurrentLyrics() async -> Int? {
        guard let lyrics = currentLyrics, lyrics.isSynced,
              let fileURL = await player.localAudioFileURLForCurrentTrack(),
              let audioFile = try? AVAudioFile(forReading: fileURL) else {
            return nil
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let maxFrames = min(AVAudioFrameCount(audioFile.length), AVAudioFrameCount(sampleRate * 90))
        guard maxFrames > 1024,
              let pcm = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: maxFrames) else {
            return nil
        }
        do {
            try audioFile.read(into: pcm, frameCount: maxFrames)
        } catch {
            return nil
        }
        guard let ch0 = pcm.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: ch0, count: Int(pcm.frameLength)))
        let estimated = LyricsAutoSync.estimateOffsetMs(monoPCM: samples, sampleRate: sampleRate, lyrics: lyrics)
        updateCurrentLyricsOffset(estimated)
        return estimated
    }

    public func loadVideoStreamsForCurrent() async {
        guard let id = player.currentItem?.id else { return }
        if songEditsById[id]?.noVideo == true {
            videoStreamOptions = []
            return
        }
        if let streams = try? await resolver.resolveVideoStreams(videoId: id) {
            videoStreamOptions = streams
        }
    }

    // MARK: - Library Mutations, Persistent Local Audio Import & Importers

    public func pinCurrentToSpeedDial() {
        guard let item = player.currentItem else { return }
        try? database.pinToSpeedDial(
            SpeedDialItem(
                id: item.id,
                title: item.title,
                subtitle: item.artist,
                thumbnailUrl: item.thumbnailURL,
                type: "song"
            )
        )
        refreshLocalLibrary()
    }

    public func toggleLike(songId: String) {
        let newLikedState: Bool
        if (try? database.fetchSong(id: songId)) == nil, let item = player.currentItem, item.id == songId {
            try? database.upsertSong(
                SongEntity(
                    id: item.id,
                    title: item.title,
                    duration: item.durationSeconds ?? -1,
                    thumbnailUrl: item.thumbnailURL,
                    albumName: item.album,
                    liked: true,
                    likedDate: Int64(Date().timeIntervalSince1970 * 1000)
                )
            )
            newLikedState = true
        } else {
            newLikedState = (try? database.toggleLike(songId: songId)) ?? false
        }
        refreshLocalLibrary()
        Task {
            try? await syncManager.setRemoteLikeStatus(videoId: songId, liked: newLikedState)
        }
    }

    /// Copies imported security-scoped files into `ApplicationSupport/LocalAudio/` (preserving sandbox access
    /// permanently across app relaunches & IPA updates) and reads ID3/MP4/FLAC metadata via `AVURLAsset`.
    public func importLocalAudio(urls: [URL]) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let localDir = appSupport.appendingPathComponent("LocalAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
            let fileUUID = UUID().uuidString.lowercased()
            let destFileName = "\(fileUUID).\(ext)"
            let destURL = localDir.appendingPathComponent(destFileName)

            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)

                // Copy matching sidecar `.lrc` / `.ttml` next to the audio file if accessible.
                for sidecarExt in ["ttml", "lrc"] {
                    let srcSidecar = url.deletingPathExtension().appendingPathExtension(sidecarExt)
                    if FileManager.default.fileExists(atPath: srcSidecar.path) {
                        let dstSidecar = destURL.deletingPathExtension().appendingPathExtension(sidecarExt)
                        try? FileManager.default.copyItem(at: srcSidecar, to: dstSidecar)
                    }
                }
            } catch {
                continue
            }

            let songId = "LOCAL_\(fileUUID)"
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let relativeURI = "relative://LocalAudio/\(destFileName)"

            // Insert immediately so UI updates instantly, then enrich tags asynchronously via AVURLAsset.
            let initialSong = SongEntity(
                id: songId,
                title: fallbackTitle,
                duration: -1,
                isLocal: true,
                localUri: relativeURI
            )
            try? database.upsertSong(initialSong, artists: [ArtistEntity(id: "local-artist", name: "Local Audio", isLocal: true)])

            Task {
                let asset = AVURLAsset(url: destURL)
                let dur = (try? await asset.load(.duration)).map { $0.seconds.isFinite ? Int($0.seconds) : -1 } ?? -1
                let meta = (try? await asset.load(.commonMetadata)) ?? []
                var metaTitle = fallbackTitle
                var metaArtist = "Local Audio"
                var metaAlbum: String?

                for item in meta {
                    guard let commonKey = item.commonKey else { continue }
                    if commonKey == .commonKeyTitle, let val = try? await item.load(.stringValue), !val.isEmpty {
                        metaTitle = val
                    } else if commonKey == .commonKeyArtist, let val = try? await item.load(.stringValue), !val.isEmpty {
                        metaArtist = val
                    } else if commonKey == .commonKeyAlbumName, let val = try? await item.load(.stringValue), !val.isEmpty {
                        metaAlbum = val
                    }
                }
                let enriched = SongEntity(
                    id: songId,
                    title: metaTitle,
                    duration: dur,
                    albumName: metaAlbum,
                    isLocal: true,
                    localUri: relativeURI
                )
                try? self.database.upsertSong(
                    enriched,
                    artists: [ArtistEntity(id: "local-a-\(metaArtist.lowercased())", name: metaArtist, isLocal: true)]
                )
                self.refreshLocalLibrary()
            }
        }
        refreshLocalLibrary()
    }

    public func createPlaylist(name: String, initialSongIds: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let playlist = PlaylistEntity(name: trimmed, isLocal: true)
        try? database.upsertPlaylist(playlist)
        for (idx, songId) in initialSongIds.enumerated() {
            try? database.addSongToPlaylist(playlistId: playlist.id, songId: songId, position: idx)
        }
        refreshLocalLibrary()
    }

    public func saveSongEdit(_ edit: SongEdit) {
        try? database.upsertSongEdit(edit)
        refreshLocalLibrary()
    }

    // MARK: - Real End-to-End Playlist Importers & YouTube Sync

    public func runPlaylistImport(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isImportingPlaylist else { return }
        isImportingPlaylist = true
        importStatusMessage = nil
        importProgress = ImportProgressUpdate(stage: "Starting import...", matchedCount: 0, totalCount: 0)
        defer { isImportingPlaylist = false }

        do {
            let result = try await playlistImporter.importFromURL(trimmed) { [weak self] update in
                Task { @MainActor in self?.importProgress = update }
            }
            importStatusMessage = "Imported \"\(result.playlistName)\": \(result.matchedCount)/\(result.totalCount) tracks matched."
            refreshLocalLibrary()
        } catch {
            importStatusMessage = error.localizedDescription
        }
    }

    public func runCSVImport(csvText: String, playlistName: String) async {
        guard !isImportingPlaylist else { return }
        isImportingPlaylist = true
        importStatusMessage = nil
        importProgress = ImportProgressUpdate(stage: "Parsing CSV...", matchedCount: 0, totalCount: 0)
        defer { isImportingPlaylist = false }

        do {
            let result = try await playlistImporter.importFromCSV(csvText: csvText, playlistName: playlistName) { [weak self] update in
                Task { @MainActor in self?.importProgress = update }
            }
            importStatusMessage = "Imported CSV \"\(result.playlistName)\": \(result.matchedCount)/\(result.totalCount) tracks."
            refreshLocalLibrary()
        } catch {
            importStatusMessage = error.localizedDescription
        }
    }

    public func applyYouTubeLogin(cookie: String, visitorData: String?, dataSyncId: String?) async {
        try? SecretVault.set(cookie, for: .ytmCookie)
        if let visitorData, !visitorData.isEmpty {
            try? SecretVault.set(visitorData, for: .ytmVisitorData)
        }
        if let dataSyncId, !dataSyncId.isEmpty {
            try? SecretVault.set(dataSyncId, for: .ytmDataSyncId)
        }
        await innerTube.updateAuth(cookie: cookie, visitorData: visitorData, dataSyncId: dataSyncId)
        isSignedInToYouTube = !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        syncStatusMessage = isSignedInToYouTube ? "Signed in to YouTube Music." : "Signed out."
        await reloadHomeFeed()
    }

    public func signOutYouTube() async {
        try? SecretVault.delete(.ytmCookie)
        try? SecretVault.delete(.ytmDataSyncId)
        let guestVisitor = await innerTube.visitorData
        await innerTube.updateAuth(cookie: nil, visitorData: guestVisitor, dataSyncId: nil)
        isSignedInToYouTube = false
        syncStatusMessage = "Signed out of YouTube Music."
        await reloadHomeFeed()
    }

    public func runYouTubeLibrarySync() async {
        syncStatusMessage = "Syncing YouTube Music library..."
        do {
            let summary = try await syncManager.syncLibrary(excludeImportedPlaylists: settings.ytExcludeImports)
            canUndoLastSync = (await syncManager.latestUndoSnapshot()) != nil
            syncStatusMessage = "Synced \(summary.importedTracks) tracks & \(summary.importedPlaylists) playlists."
            refreshLocalLibrary()
        } catch {
            syncStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    public func undoYouTubeLibrarySync() async {
        do {
            let reverted = try await syncManager.undoLastSync()
            canUndoLastSync = false
            syncStatusMessage = reverted ? "Reverted last YouTube Music sync." : "Nothing to undo."
            refreshLocalLibrary()
        } catch {
            syncStatusMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Profile Avatar Persistence

    public func saveProfileAvatar(data: Data) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dest = appSupport.appendingPathComponent("profile_avatar.jpg")
        try? data.write(to: dest, options: .atomic)
        settings.profileAvatarPath = "profile_avatar.jpg"
    }

    public func profileAvatarURL() -> URL? {
        guard let rel = settings.profileAvatarPath, !rel.isEmpty,
              let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = appSupport.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func saveTrackMetadataToDB(_ track: YTTrackItem) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let existing = try? database.fetchSong(id: track.id)
        let upgradedThumb = ThumbnailURLUpgrader.upgrade(track.thumbnailURL) ?? existing?.thumbnailUrl
        let song = SongEntity(
            id: track.id,
            title: track.title,
            duration: track.durationSeconds ?? existing?.duration ?? -1,
            thumbnailUrl: upgradedThumb,
            albumId: existing?.albumId,
            albumName: track.album ?? existing?.albumName,
            explicit: track.explicit || (existing?.explicit ?? false),
            year: existing?.year,
            date: existing?.date,
            dateModified: nowMs,
            liked: existing?.liked ?? false,
            likedDate: existing?.likedDate,
            totalPlayTime: existing?.totalPlayTime ?? 0,
            inLibrary: existing?.inLibrary ?? nowMs,
            dateDownload: existing?.dateDownload,
            isLocal: existing?.isLocal ?? false,
            libraryAddToken: existing?.libraryAddToken,
            libraryRemoveToken: existing?.libraryRemoveToken,
            lyricsOffset: existing?.lyricsOffset ?? 0,
            romanizeLyrics: existing?.romanizeLyrics ?? true,
            isDownloaded: existing?.isDownloaded ?? false,
            isUploaded: existing?.isUploaded ?? false,
            isVideo: track.isVideo || (existing?.isVideo ?? false),
            localUri: existing?.localUri,
            addedByLike: existing?.addedByLike ?? false,
            genre: existing?.genre
        )
        let artists = track.artists.map { name in
            ArtistEntity(id: "yt-a-\(name.lowercased())", name: name, thumbnailUrl: upgradedThumb)
        }
        try? database.upsertSong(song, artists: artists)
        refreshLocalLibrary()
    }

    public func reloadHomeFeed() async {
        isLoadingHome = true
        defer { isLoadingHome = false }
        let topArtists = (try? database.fetchTopArtists(limit: 5))?.map(\.artist.name) ?? []
        let sections = await innerTube.loadRichHomeFeed(
            isSignedIn: isSignedInToYouTube,
            topLocalArtists: topArtists,
            countryCode: settings.countryCode,
            languageCode: settings.languageCode
        )
        if !sections.isEmpty {
            homeSections = sections
        }
    }

    public func toggleDislikeCurrentTrack() {
        guard let item = player.currentItem else { return }
        if dislikedSongIds.contains(item.id) {
            dislikedSongIds.remove(item.id)
            showMenuToast("Removed dislike")
        } else {
            dislikedSongIds.insert(item.id)
            if isLiked(songId: item.id) {
                toggleLike(songId: item.id)
            }
            let trackId = item.id
            Task { try? await syncManager.setRemoteLikeStatus(videoId: trackId, liked: false) }
            showMenuToast("Disliked · Skipping next")
            player.skipNext()
        }
    }

    public func startRadioForCurrentTrack() async {
        guard let item = player.currentItem else { return }
        showMenuToast("Starting radio...")
        let radioTracks = (try? await innerTube.nextQueue(videoId: item.id)) ?? []
        let playbackItems = radioTracks.map(PlaybackItem.init(ytTrack:))
        guard !playbackItems.isEmpty else {
            showMenuToast("Couldn't start radio")
            return
        }
        playingFromLabel = "Radio · \(item.title)"
        player.playQueue(playbackItems, startIndex: 0, playlistId: "RDAMVM\(item.id)")
    }

    public func addCurrentTrackToPlaylist(playlistId: String) {
        guard let item = player.currentItem else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if (try? database.fetchSong(id: item.id)) == nil {
            let song = SongEntity(
                id: item.id,
                title: item.title,
                duration: item.durationSeconds ?? -1,
                thumbnailUrl: ThumbnailURLUpgrader.upgrade(item.thumbnailURL, size: 720),
                albumName: item.album,
                dateModified: nowMs,
                inLibrary: nowMs
            )
            let artist = ArtistEntity(id: "yt-a-\(item.artist.lowercased())", name: item.artist, thumbnailUrl: song.thumbnailUrl)
            try? database.upsertSong(song, artists: [artist])
        }
        try? database.addSongToPlaylist(playlistId: playlistId, songId: item.id)
        refreshLocalLibrary()
        showMenuToast("Added to playlist")
    }

    public func downloadCurrentTrackToCache() async {
        guard let item = player.currentItem else { return }
        if downloadedSongIds.contains(item.id) {
            showMenuToast("Already cached offline")
            return
        }
        showMenuToast("Caching offline...")
        if let localURL = await player.localAudioFileURLForCurrentTrack(),
           let data = try? Data(contentsOf: localURL), !data.isEmpty {
            let ext = localURL.pathExtension.isEmpty ? "m4a" : localURL.pathExtension
            try? await player.chunkCache.markCompleted(mediaId: item.id, fileExtension: ext, fullFileData: data)
            await refreshDownloadedState()
            showMenuToast("Saved for offline playback")
        } else {
            showMenuToast("Play track briefly to cache")
        }
    }

    public func clearCacheForCurrentTrack() async {
        guard let item = player.currentItem else { return }
        await player.chunkCache.removeMedia(mediaId: item.id)
        await refreshDownloadedState()
        showMenuToast("Removed from audio cache")
    }

    public func openInAppSearch(query: String) {
        isPlayerExpanded = false
        playerDragProgress = 0
        searchQuery = query
        selectedTab = .search
        searchFocusTrigger += 1
        Task { await runSearch(query: query) }
    }

    public func buildCurrentTrackDiagnosticLog() -> String {
        let item = player.currentItem
        return [
            "Title: \(item?.title ?? "—")",
            "Artist: \(item?.artist ?? "—")",
            "Track ID: \(item?.id ?? "—")",
            "Source: \(player.activeSourceLabel.isEmpty ? "—" : player.activeSourceLabel)",
            "Quality: \(player.activeQualityBadge.isEmpty ? "—" : player.activeQualityBadge)",
            "Position: \(Int(player.currentTime))s / \(Int(player.duration))s",
            "Locale: \(settings.languageCode)-\(settings.countryCode)",
            "Last Error: \(player.lastError ?? "None")"
        ].joined(separator: "\n")
    }

    public func showMenuToast(_ message: String) {
        menuToastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if self.menuToastMessage == message {
                self.menuToastMessage = nil
            }
        }
    }

    private func updatePalette(from urlString: String?) async {
        guard let upgraded = ThumbnailURLUpgrader.upgrade(urlString, size: 360),
              let url = URL(string: upgraded),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return
        }
        paletteColors = ArtworkPaletteExtractor.extractColors(fromImageData: data)
    }
}
