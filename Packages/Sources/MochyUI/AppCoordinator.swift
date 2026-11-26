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
        case .library: return "square.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
public final class AppCoordinator {
    public var settings: AppSettings
    public let database: MochyDatabase
    public let innerTube: InnerTubeClient
    public let resolver: YTPlayerResolver
    public let router: SourceModulesRouter
    public var player: MochyAudioPlayer
    public let lyricsHelper: LyricsHelper
    public let lyricsTranslator: LyricsTranslator
    public let syncManager: YouTubeSyncManager
    public let shazam: ShazamRecognizer
    public let linkService: MochyLinkService
    public let scrobbler: LastFmScrobbler
    public let discord: DiscordPresenceClient

    // Navigation & Player Sheet Motion
    public var selectedTab: RootNavTab = .home
    public var isPlayerExpanded: Bool = false
    public var playerDragProgress: CGFloat = 0 // 0 = collapsed, 1 = expanded
    public var searchFocusTrigger: Int = 0

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
    public var speedDialItems: [SpeedDialItem] = []
    public var songEditsById: [String: SongEdit] = [:]

    public var currentLyrics: LyricsDocument?
    public var isLoadingLyrics = false
    public var lyricsTargetLang = "vi"
    public var paletteColors: [Color] = [MochyTheme.defaultAccent, .indigo, .purple, .black]
    public var currentModuleSkin: ModuleSkinManifest = .defaultSkin
    public var videoStreamOptions: [YTVideoStreamOption] = []

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
            locale: YouTubeLocale(),
            cookie: cookie,
            visitorData: visitor,
            dataSyncId: dataSync
        )
        self.innerTube = yt
        self.resolver = YTPlayerResolver(innerTube: yt)
        self.router = SourceModulesRouter(youtubeResolver: self.resolver)
        self.player = MochyAudioPlayer(settings: settings, router: self.router, database: database)
        self.lyricsHelper = LyricsHelper(lastResortProvider: YouTubeCaptionsLyricsProvider(innerTube: yt))
        self.lyricsTranslator = LyricsTranslator()
        self.syncManager = YouTubeSyncManager(innerTube: yt, database: database)
        self.shazam = ShazamRecognizer(database: database)
        self.linkService = MochyLinkService()
        self.scrobbler = LastFmScrobbler()
        self.discord = DiscordPresenceClient()

        refreshLocalLibrary()
    }

    public func onSelectTab(_ tab: RootNavTab) {
        if tab == .search && selectedTab == .search {
            searchFocusTrigger += 1
        }
        selectedTab = tab
    }

    public func refreshLocalLibrary() {
        librarySongs = (try? database.fetchAllSongs()) ?? []
        libraryPlaylists = (try? database.fetchPlaylists()) ?? []
        speedDialItems = (try? database.fetchSpeedDialItems()) ?? []
        recentSearches = (try? database.recentSearches()) ?? []
        let edits = (try? database.fetchAllSongEdits()) ?? []
        songEditsById = Dictionary(uniqueKeysWithValues: edits.map { ($0.songId, $0) })
    }

    public func loadHomeFeedIfNeeded() async {
        guard homeSections.isEmpty, !isLoadingHome else { return }
        isLoadingHome = true
        defer { isLoadingHome = false }
        if let sections = try? await innerTube.browseHome() {
            self.homeSections = sections
        }
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

    public func playTrack(_ track: YTTrackItem, queueContext: [YTTrackItem]? = nil) {
        let items = (queueContext ?? [track]).map(PlaybackItem.init(ytTrack:))
        let startIdx = queueContext?.firstIndex(where: { $0.id == track.id }) ?? 0
        player.playQueue(items, startIndex: startIdx)
        saveTrackMetadataToDB(track)
        onTrackChanged()
    }

    public func playLocalSong(_ song: SongEntity, allSongs: [SongEntity]) {
        let items = allSongs.map { s -> PlaybackItem in
            let edit = songEditsById[s.id]
            let artists = (try? database.fetchArtistsForSong(songId: s.id).map(\.name)) ?? []
            var item = PlaybackItem(song: s, artistNames: artists)
            if let editedTitle = edit?.title {
                item = PlaybackItem(
                    id: item.id,
                    title: editedTitle,
                    artist: edit?.artists ?? item.artist,
                    album: edit?.album ?? item.album,
                    durationSeconds: item.durationSeconds,
                    thumbnailURL: edit?.cover ?? item.thumbnailURL,
                    localFileURL: item.localFileURL
                )
            }
            return item
        }
        let startIdx = allSongs.firstIndex(where: { $0.id == song.id }) ?? 0
        player.playQueue(items, startIndex: startIdx)
        onTrackChanged()
    }

    public func onTrackChanged() {
        guard let item = player.currentItem, item.id != lastLoadedTrackId else { return }
        lastLoadedTrackId = item.id
        currentLyrics = nil
        videoStreamOptions = []

        Task {
            await loadLyricsForCurrentTrack()
            await updatePalette(from: item.thumbnailURL)
            await scrobbler.enqueueScrobble(artist: item.artist, track: item.title)
            await discord.updateListeningPresence(title: item.title, artist: item.artist, durationSeconds: item.durationSeconds)
        }
    }

    public func loadLyricsForCurrentTrack() async {
        guard let item = player.currentItem else { return }
        isLoadingLyrics = true
        defer { isLoadingLyrics = false }

        if let cached = try? database.fetchLyrics(id: item.id),
           let parsed = LRCParser.parse(cached.lyrics, provider: cached.provider) {
            currentLyrics = settings.lyricsRomanize ? LyricsRomanizer.romanizedDocument(parsed) : parsed
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
                doc = await lyricsTranslator.translate(document: doc, targetLanguage: lyricsTargetLang)
            }
            currentLyrics = doc
            try? database.upsertLyrics(
                LyricsEntity(id: item.id, lyrics: doc.plainText, provider: doc.sourceProvider)
            )
        }
    }

    public func loadVideoStreamsForCurrent() async {
        guard let id = player.currentItem?.id else { return }
        if let streams = try? await resolver.resolveVideoStreams(videoId: id) {
            videoStreamOptions = streams
        }
    }

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
        } else {
            _ = try? database.toggleLike(songId: songId)
        }
        refreshLocalLibrary()
    }

    public func importLocalAudio(urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let id = "LOCAL_\(url.lastPathComponent.hashValue)"
            let title = url.deletingPathExtension().lastPathComponent
            let song = SongEntity(
                id: id,
                title: title,
                duration: -1,
                isLocal: true,
                localUri: url.absoluteString
            )
            try? database.upsertSong(song, artists: [ArtistEntity(id: "local-artist", name: "Local File", isLocal: true)])
        }
        refreshLocalLibrary()
    }

    public func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? database.upsertPlaylist(PlaylistEntity(name: trimmed, isLocal: true))
        refreshLocalLibrary()
    }

    public func saveSongEdit(_ edit: SongEdit) {
        try? database.upsertSongEdit(edit)
        refreshLocalLibrary()
    }

    private func saveTrackMetadataToDB(_ track: YTTrackItem) {
        let song = SongEntity(
            id: track.id,
            title: track.title,
            duration: track.durationSeconds ?? -1,
            thumbnailUrl: track.thumbnailURL,
            albumName: track.album,
            explicit: track.explicit,
            isVideo: track.isVideo
        )
        let artists = track.artists.map { name in
            ArtistEntity(id: "yt-a-\(name.lowercased())", name: name)
        }
        try? database.upsertSong(song, artists: artists)
        refreshLocalLibrary()
    }

    private func updatePalette(from urlString: String?) async {
        guard let urlString, let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return
        }
        paletteColors = ArtworkPaletteExtractor.extractColors(fromImageData: data)
    }
}
