import MochyAudio
import MochyCore
import MochyDatabase
import MochyInnerTube
import MochyLyrics
import MochySync
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Home Screen (MOCHYY / LISTEN_NOW / HOP_IN + SpeedDialHero)

public struct HomeScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var showStats = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    homeHeader
                    speedDialSection

                    if coordinator.isLoadingHome && coordinator.homeSections.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading YouTube Music feed...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if !coordinator.librarySongs.isEmpty {
                        recentLibraryShelf
                    }

                    ForEach(coordinator.homeSections) { section in
                        sectionCarousel(section)
                    }

                    recapBanner
                }
                .padding(.bottom, 150)
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .refreshable {
                coordinator.homeSections = []
                await coordinator.loadHomeFeedIfNeeded()
            }
            .sheet(isPresented: $showStats) {
                StatsAndRecapView(coordinator: coordinator)
            }
        }
    }

    private var homeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(homeTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Free • No Ads • High-Res Ready")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Picker("Home Style", selection: $coordinator.settings.homeStyle) {
                Text("Mochyy").tag(HomeStyle.mochyy)
                Text("Listen Now").tag(HomeStyle.listenNow)
                Text("Hop In").tag(HomeStyle.hopIn)
            }
            .pickerStyle(.menu)
            .tint(.white)

            Button {
                showStats = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(MochyTheme.elevatedSurface, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var homeTitle: String {
        switch coordinator.settings.homeStyle {
        case .mochyy: return "Natch Music"
        case .listenNow: return "Listen Now"
        case .hopIn: return "Hop In"
        }
    }

    @ViewBuilder
    private var speedDialSection: some View {
        if !coordinator.speedDialItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Speed Dial")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: coordinator.settings.homeStyle == .hopIn ? 3 : 2)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(coordinator.speedDialItems, id: \.id) { item in
                        Button {
                            let playback = PlaybackItem(
                                id: item.id,
                                title: item.title,
                                artist: item.subtitle ?? "Unknown",
                                thumbnailURL: item.thumbnailUrl
                            )
                            coordinator.player.playQueue([playback])
                            coordinator.onTrackChanged()
                        } label: {
                            HStack(spacing: 10) {
                                ArtworkImageView(urlString: item.thumbnailUrl, cornerRadius: 8)
                                    .frame(width: 44, height: 44)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recentLibraryShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Added & Played")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(coordinator.librarySongs.prefix(12), id: \.id) { song in
                        Button {
                            coordinator.playLocalSong(song, allSongs: coordinator.librarySongs)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkImageView(
                                    urlString: coordinator.songEditsById[song.id]?.cover ?? song.thumbnailUrl,
                                    cornerRadius: coordinator.settings.thumbnailCornerRadius
                                )
                                .frame(width: 128, height: 128)
                                Text(coordinator.songEditsById[song.id]?.title ?? song.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .frame(width: 128)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func sectionCarousel(_ section: YTHomeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(section.items) { track in
                        Button {
                            coordinator.playTrack(track, queueContext: section.items)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkImageView(
                                    urlString: track.thumbnailURL,
                                    cornerRadius: coordinator.settings.thumbnailCornerRadius
                                )
                                .frame(width: 136, height: 136)
                                Text(track.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(track.artistDisplay)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            .frame(width: 136)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recapBanner: some View {
        Button {
            showStats = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Natch Recap & Profile Card")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Listening time, top songs, and 3D flip USR# card")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(MochyTheme.defaultAccent)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [MochyTheme.defaultAccent.opacity(0.32), Color(white: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .padding(.horizontal)
    }
}

// MARK: - Search Screen (Online YouTube / Local + Suggestions + Shazam)

public struct SearchScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @FocusState private var isSearchFocused: Bool
    @State private var onlineMode = true
    @State private var importLinkText = ""
    @State private var linkImportBanner: String?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Songs, artists, YouTube URL...", text: $coordinator.searchQuery)
                            .focused($isSearchFocused)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task { await coordinator.runSearch() }
                            }
                    }
                    .padding(10)
                    .background(MochyTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))

                    Button {
                        Task { await coordinator.shazam.recognizeCurrentMicrophone() }
                    } label: {
                        Image(systemName: coordinator.shazam.isListening ? "waveform.circle.fill" : "shazam.logo.fill")
                            .font(.title2)
                            .foregroundStyle(MochyTheme.defaultAccent)
                            .padding(8)
                            .background(MochyTheme.cardSurface, in: Circle())
                    }
                }
                .padding(.horizontal)

                if coordinator.shazam.isListening || coordinator.shazam.latestMatch != nil {
                    Text(coordinator.shazam.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal)
                }

                Picker("Scope", selection: $onlineMode) {
                    Text("YouTube Music").tag(true)
                    Text("Local Library").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if onlineMode {
                            if !coordinator.searchSuggestions.isEmpty && coordinator.searchResults.isEmpty {
                                ForEach(coordinator.searchSuggestions, id: \.self) { sugg in
                                    Button {
                                        Task { await coordinator.runSearch(query: sugg) }
                                    } label: {
                                        Label(sugg, systemImage: "magnifyingglass")
                                            .foregroundStyle(.white.opacity(0.85))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal)
                                    }
                                }
                            }

                            if coordinator.isSearching {
                                ProgressView("Searching...").padding()
                            } else {
                                ForEach(coordinator.searchResults) { track in
                                    trackRow(track)
                                }
                            }

                            if coordinator.searchResults.isEmpty && !coordinator.recentSearches.isEmpty {
                                Text("Recent Searches")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding([.horizontal, .top])
                                ForEach(coordinator.recentSearches, id: \.self) { recent in
                                    Button {
                                        Task { await coordinator.runSearch(query: recent) }
                                    } label: {
                                        Label(recent, systemImage: "clock.arrow.circlepath")
                                            .foregroundStyle(.white.opacity(0.75))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        } else {
                            let filtered = coordinator.librarySongs.filter {
                                coordinator.searchQuery.isEmpty ||
                                $0.title.localizedCaseInsensitiveContains(coordinator.searchQuery)
                            }
                            ForEach(filtered, id: \.id) { song in
                                Button {
                                    coordinator.playLocalSong(song, allSongs: filtered)
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                                            .frame(width: 48, height: 48)
                                        Text(song.title)
                                            .foregroundStyle(.white)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 150)
                }
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .navigationTitle("Search")
            .onChange(of: coordinator.searchFocusTrigger) { _, _ in
                isSearchFocused = true
            }
            .onChange(of: coordinator.searchQuery) { _, newValue in
                Task { await coordinator.updateSuggestions(for: newValue) }
            }
        }
    }

    private func trackRow(_ track: YTTrackItem) -> some View {
        HStack(spacing: 12) {
            Button {
                coordinator.playTrack(track, queueContext: coordinator.searchResults)
            } label: {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: track.thumbnailURL, cornerRadius: 10)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artistDisplay)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            Menu {
                Button("Add to Queue") {
                    coordinator.player.appendToQueue(PlaybackItem(ytTrack: track))
                }
                Button("Pin to Speed Dial") {
                    try? coordinator.database.pinToSpeedDial(
                        SpeedDialItem(
                            id: track.id,
                            title: track.title,
                            subtitle: track.artistDisplay,
                            thumbnailUrl: track.thumbnailURL,
                            type: "song"
                        )
                    )
                    coordinator.refreshLocalLibrary()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Library Screen (Songs / Playlists / Local Audio / IndexGlide / SongEdit)

public struct LibraryScreen: View {
    public enum Filter: String, CaseIterable {
        case songs = "Songs"
        case playlists = "Playlists"
        case liked = "Liked"
        case local = "Local"
    }

    @Bindable public var coordinator: AppCoordinator
    @State private var filter: Filter = .songs
    @State private var showFileImporter = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var editingSong: SongEntity?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Button {
                                filter = f
                            } label: {
                                Text(f.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(filter == f ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(filter == f ? Color.white : MochyTheme.cardSurface, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if filter == .playlists {
                    List {
                        ForEach(coordinator.libraryPlaylists, id: \.id) { playlist in
                            NavigationLink {
                                PlaylistDetailView(coordinator: coordinator, playlist: playlist)
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(MochyTheme.defaultAccent)
                                    VStack(alignment: .leading) {
                                        Text(playlist.name).foregroundStyle(.white)
                                        Text(playlist.mixItEnabled ? "MixIt DJ Enabled" : "Playlist")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .listRowBackground(MochyTheme.cardSurface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    let songs = filteredSongs
                    ScrollViewReader { proxy in
                        HStack(spacing: 0) {
                            List {
                                ForEach(songs, id: \.id) { song in
                                    songRow(song, allSongs: songs)
                                        .id(song.id)
                                        .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)

                            if songs.count >= 6 {
                                indexGlideRail(songs: songs, proxy: proxy)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 120)
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus.rectangle.on.folder")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    coordinator.importLocalAudio(urls: urls)
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create") {
                    coordinator.createPlaylist(name: newPlaylistName)
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editingSong) { song in
                SongEditSheet(coordinator: coordinator, song: song)
            }
        }
    }

    private var filteredSongs: [SongEntity] {
        switch filter {
        case .songs: return coordinator.librarySongs
        case .liked: return coordinator.librarySongs.filter(\.liked)
        case .local: return coordinator.librarySongs.filter(\.isLocal)
        case .playlists: return []
        }
    }

    private func songRow(_ song: SongEntity, allSongs: [SongEntity]) -> some View {
        let edit = coordinator.songEditsById[song.id]
        return Button {
            coordinator.playLocalSong(song, allSongs: allSongs)
        } label: {
            HStack(spacing: 12) {
                ArtworkImageView(urlString: edit?.cover ?? song.thumbnailUrl, cornerRadius: 8)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(edit?.title ?? song.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(edit?.artists ?? song.albumName ?? (song.isLocal ? "Local File" : "Library Track"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if song.liked {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(MochyTheme.defaultAccent)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Edit") { editingSong = song }.tint(.blue)
            Button("Like") { coordinator.toggleLike(songId: song.id) }.tint(MochyTheme.defaultAccent)
        }
    }

    private func indexGlideRail(songs: [SongEntity], proxy: ScrollViewProxy) -> some View {
        let letters = ["A", "D", "H", "L", "M", "S", "T", "Z"]
        return VStack(spacing: 4) {
            ForEach(letters, id: \.self) { ch in
                Button {
                    if let target = songs.first(where: { $0.title.uppercased() >= ch }) {
                        withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                    }
                } label: {
                    Text(ch)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .padding(.trailing, 4)
    }
}

private struct SongEditSheet: View {
    @Bindable var coordinator: AppCoordinator
    let song: SongEntity
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var artists: String
    @State private var album: String
    @State private var noVideo: Bool

    init(coordinator: AppCoordinator, song: SongEntity) {
        self.coordinator = coordinator
        self.song = song
        let edit = coordinator.songEditsById[song.id]
        _title = State(initialValue: edit?.title ?? song.title)
        _artists = State(initialValue: edit?.artists ?? "")
        _album = State(initialValue: edit?.album ?? song.albumName ?? "")
        _noVideo = State(initialValue: edit?.noVideo ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Non-Destructive Metadata Override (`song_edit`)") {
                    TextField("Custom Title", text: $title)
                    TextField("Custom Artists", text: $artists)
                    TextField("Custom Album", text: $album)
                    Toggle("Disable Music Video Swap", isOn: $noVideo)
                }
            }
            .navigationTitle("Edit Track Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.saveSongEdit(
                            SongEdit(
                                songId: song.id,
                                title: title.isEmpty ? nil : title,
                                artists: artists.isEmpty ? nil : artists,
                                album: album.isEmpty ? nil : album,
                                noVideo: noVideo
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Playlist Detail View & Stats / 3D Profile ID Card

public struct PlaylistDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let playlist: PlaylistEntity
    @State private var songs: [SongEntity] = []
    @State private var showMixIt = false

    public var body: some View {
        List {
            Section {
                Button {
                    showMixIt = true
                } label: {
                    Label("Open MixIt Transition Studio", systemImage: "slider.horizontal.2.waveform")
                        .foregroundStyle(MochyTheme.defaultAccent)
                }
            }
            Section("Tracks (\(songs.count))") {
                ForEach(songs, id: \.id) { song in
                    Button {
                        coordinator.playLocalSong(song, allSongs: songs)
                    } label: {
                        Text(song.title).foregroundStyle(.white)
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .onAppear {
            songs = (try? coordinator.database.fetchPlaylistSongs(playlistId: playlist.id)) ?? []
        }
        .sheet(isPresented: $showMixIt) {
            MixItEditorSheet(coordinator: coordinator, playlist: playlist, songs: songs)
        }
    }
}

public struct StatsAndRecapView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var totalMs: Int64 = 0
    @State private var topSongs: [SongEntity] = []
    @State private var cardFlipped = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 3D Flipping USR# Profile ID Card
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [MochyTheme.defaultAccent, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        if !cardFlipped {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("NATCH ID CARD")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text("USR#1308")
                                        .font(.caption.monospaced())
                                }
                                Spacer()
                                Text("\(totalMs / 60_000) mins listened")
                                    .font(.title2.bold())
                                Text("Tap card to flip for Recap stats")
                                    .font(.caption2)
                            }
                            .padding(20)
                            .foregroundStyle(.white)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("MONTHLY RECAP")
                                    .font(.caption.bold())
                                Text("Tracks in Library: \(coordinator.librarySongs.count)")
                                Text("Top Track: \(topSongs.first?.title ?? "Start playing!")")
                                Spacer()
                                Text("100% Free & Open Source")
                                    .font(.caption2)
                            }
                            .padding(20)
                            .foregroundStyle(.white)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        }
                    }
                    .frame(height: 175)
                    .rotation3DEffect(.degrees(cardFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            cardFlipped.toggle()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top Played Tracks")
                            .font(.headline)
                        ForEach(topSongs, id: \.id) { song in
                            HStack {
                                Text(song.title).lineLimit(1)
                                Spacer()
                                Text("\(song.totalPlayTime / 1000)s")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Recap & Stats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                totalMs = (try? coordinator.database.fetchTotalPlayTimeMs()) ?? 0
                topSongs = (try? coordinator.database.fetchTopSongs(limit: 15)) ?? []
            }
        }
    }
}

// MARK: - Settings & About (GPL-3.0 Attribution)

public struct SettingsScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var schemaHealth: SchemaHealth?
    @State private var linkToImport = ""
    @State private var importFeedback: String?

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appearance & Player Style") {
                    Picker("Player Style (10 Presets)", selection: $coordinator.settings.playerStyle) {
                        ForEach(PlayerStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Picker("Background", selection: $coordinator.settings.flagshipBackground) {
                        ForEach(FlagshipBackground.allCases, id: \.self) { bg in
                            Text(bg.rawValue).tag(bg)
                        }
                    }
                    Picker("Seekbar Style", selection: $coordinator.settings.seekbarStyle) {
                        ForEach(SeekbarStyle.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    Toggle("Pure Black OLED", isOn: $coordinator.settings.pureBlack)
                    Slider(value: $coordinator.settings.thumbnailCornerRadius, in: 0...32, step: 1) {
                        Text("Corner Radius: \(Int(coordinator.settings.thumbnailCornerRadius))pt")
                    }
                }

                Section("Audio, Sources & Audio Lab") {
                    Picker("Audio Quality", selection: $coordinator.settings.audioQuality) {
                        ForEach(AudioQuality.allCases, id: \.self) { q in
                            Text(q.rawValue.uppercased()).tag(q)
                        }
                    }
                    NavigationLink("Open Audio Lab (EQ / 3D Stage / Audio Pass)") {
                        AudioLabView(coordinator: coordinator)
                    }
                    Toggle("Crossmix / MixIt", isOn: Binding(
                        get: { coordinator.settings.crossmixMode != .off },
                        set: { coordinator.settings.crossmixMode = $0 ? .classic : .off }
                    ))
                    Toggle("Offline Mode", isOn: $coordinator.settings.offlineMode)
                }

                Section("Lyrics & Translation") {
                    Picker("Motion Style", selection: $coordinator.settings.lyricsMotionStyle) {
                        ForEach(LyricsMotionStyle.allCases, id: \.self) { m in
                            Text(m.rawValue.capitalized).tag(m)
                        }
                    }
                    Toggle("Romanize CJK / Non-Latin", isOn: $coordinator.settings.lyricsRomanize)
                    Toggle("Translate Lyrics", isOn: $coordinator.settings.lyricsTranslate)
                }

                Section("Mochy Link LAN & Importers") {
                    Toggle("Bonjour Mochy Link (`_mochy-link._tcp`)", isOn: Binding(
                        get: { coordinator.linkService.isHosting },
                        set: { on in
                            if on { coordinator.linkService.startDiscoveryAndAdvertising() }
                            else { coordinator.linkService.stop() }
                        }
                    ))
                    if !coordinator.linkService.discoveredPeers.isEmpty {
                        Text("Peers: \(coordinator.linkService.discoveredPeers.joined(separator: ", "))")
                            .font(.caption)
                    }
                    HStack {
                        TextField("Spotify / Apple / YouTube URL", text: $linkToImport)
                        Button("Parse") {
                            if let parsed = LinkImporter.parse(urlString: linkToImport) {
                                importFeedback = "Detected \(parsed.service.rawValue) \(parsed.kind): \(parsed.remoteId)"
                            } else {
                                importFeedback = "Unsupported URL format."
                            }
                        }
                    }
                    if let importFeedback {
                        Text(importFeedback).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Diagnostics (SQLite v47)") {
                    if let health = schemaHealth {
                        Text("SQLite WAL: \(health.tableCount) tables, \(health.viewCount) views, v\(health.userVersion)")
                            .font(.caption.monospaced())
                    }
                }

                Section("About & Credits (GPL-3.0)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Natch Music (iOS)")
                            .font(.headline)
                        Text("Open-source port of Mochy Music (github.com/realidkroo/Mochy-Music, GPL-3.0). Built upon ViviMusic, Metrolist, InnerTune, Monochrome, yt-dlp EJS, BgUtils, AutoEq & GRDB.swift.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("100% Free Forever — Zero Paywalls, Zero Ads, Zero Locked Features.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MochyTheme.defaultAccent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 120)
            .navigationTitle("Settings")
            .onAppear {
                schemaHealth = try? coordinator.database.schemaHealthCheck()
            }
        }
    }
}
