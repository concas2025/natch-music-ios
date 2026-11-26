import MochyAudio
import MochyCore
import MochyDatabase
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum LibraryFilterChip: String, CaseIterable {
    case songs = "Songs"
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case liked = "Liked"
    case downloaded = "Downloaded"
    case local = "Local"
}

/// 1:1 Mochy Library Screen:
/// - 7 filter chips (`Songs`, `Playlists`, `Albums`, `Artists`, `Liked`, `Downloaded`, `Local`)
/// - Continuous-drag `A–Z` `IndexGlideRail` with Taptic ticks
/// - Non-destructive `SongEditSheet`, 6-style `PlaylistDetailView` + `MixItEditorSheet`, `AlbumDetailView`, `ArtistDetailView`
/// - Sandbox-safe local audio `fileImporter`
public struct LibraryScreen: View {
    @Bindable public var coordinator: AppCoordinator

    @State private var selectedChip: LibraryFilterChip = .songs
    @State private var showLocalFileImporter = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var editingSong: SongEntity?
    @State private var activeGlideLetter: String?

    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Header + Local Import + New Playlist
                HStack {
                    Text("Library")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        showLocalFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(MochyTheme.cardSurface)
                            .clipShape(Circle())
                    }
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(MochyTheme.defaultAccent)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Horizontal Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LibraryFilterChip.allCases, id: \.self) { chip in
                            let selected = selectedChip == chip
                            Button(chip.rawValue) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selectedChip = chip
                                }
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? MochyTheme.defaultAccent : MochyTheme.cardSurface)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Active Tab Content
                contentForChip
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .fileImporter(
                isPresented: $showLocalFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    coordinator.importLocalAudio(urls: urls)
                }
            }
            .alert("Create Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    coordinator.createPlaylist(name: newPlaylistName)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editingSong) { song in
                SongEditSheet(coordinator: coordinator, song: song)
            }
            .task {
                await coordinator.refreshDownloadedState()
            }
        }
    }

    @ViewBuilder
    private var contentForChip: some View {
        switch selectedChip {
        case .songs:
            songsListWithGlideRail(songs: coordinator.librarySongs)
        case .liked:
            songsListWithGlideRail(songs: coordinator.librarySongs.filter(\.liked))
        case .local:
            songsListWithGlideRail(songs: coordinator.librarySongs.filter(\.isLocal))
        case .downloaded:
            let downloaded = coordinator.librarySongs.filter { coordinator.downloadedSongIds.contains($0.id) }
            songsListWithGlideRail(songs: downloaded)
        case .playlists:
            playlistsGrid
        case .albums:
            albumsList
        case .artists:
            artistsList
        }
    }

    private func songsListWithGlideRail(songs: [SongEntity]) -> some View {
        let sorted = songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        if sorted.isEmpty {
                            Text("No tracks in this filter yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 48)
                        } else {
                            ForEach(sorted, id: \.id) { song in
                                songRow(song: song, context: sorted)
                                    .id(song.id)
                            }
                        }
                        Spacer(minLength: 150)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 28)
                }
                .onChange(of: activeGlideLetter) { _, letter in
                    guard let letter else { return }
                    if let target = sorted.first(where: { firstLetter(of: $0.title) == letter }) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }

            // Continuous Drag A-Z IndexGlideRail
            if sorted.count >= 6 {
                GeometryReader { railGeo in
                    VStack(spacing: 1) {
                        ForEach(alphabet, id: \.self) { ch in
                            Text(ch)
                                .font(.system(size: 9, weight: activeGlideLetter == ch ? .black : .semibold))
                                .foregroundStyle(activeGlideLetter == ch ? MochyTheme.defaultAccent : .white.opacity(0.45))
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let idx = Int((val.location.y / max(1, railGeo.size.height)) * CGFloat(alphabet.count))
                                let clamped = max(0, min(alphabet.count - 1, idx))
                                let letter = alphabet[clamped]
                                if activeGlideLetter != letter {
                                    activeGlideLetter = letter
                                    #if os(iOS) && canImport(UIKit)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    #endif
                                }
                            }
                            .onEnded { _ in activeGlideLetter = nil }
                    )
                }
                .frame(width: 22)
                .padding(.vertical, 16)
                .padding(.bottom, 120)
            }
        }
    }

    private func songRow(song: SongEntity, context: [SongEntity]) -> some View {
        let edit = coordinator.songEditsById[song.id]
        let displayTitle = edit?.title ?? song.title
        let displayCover = edit?.cover ?? song.thumbnailUrl

        return HStack(spacing: 12) {
            Button {
                coordinator.playLocalSong(song, allSongs: context)
            } label: {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: displayCover, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if song.isLocal {
                                Text("LOCAL")
                                    .font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.22))
                                    .foregroundStyle(.cyan)
                                    .clipShape(Capsule())
                            }
                            if coordinator.downloadedSongIds.contains(song.id) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Text(edit?.artists ?? song.albumName ?? "Track")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    coordinator.toggleLike(songId: song.id)
                } label: {
                    Label(song.liked ? "Unlike" : "Like", systemImage: song.liked ? "heart.slash" : "heart")
                }
                Button {
                    editingSong = song
                } label: {
                    Label("Edit Metadata (Non-Destructive)", systemImage: "pencil")
                }
                if !coordinator.libraryPlaylists.isEmpty {
                    Menu("Add to Playlist") {
                        ForEach(coordinator.libraryPlaylists, id: \.id) { pl in
                            Button(pl.name) {
                                try? coordinator.database.addSongToPlaylist(playlistId: pl.id, songId: song.id)
                                coordinator.refreshLocalLibrary()
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 32)
            }
        }
        .padding(.vertical, 4)
    }

    private var playlistsGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(coordinator.libraryPlaylists, id: \.id) { pl in
                    NavigationLink {
                        PlaylistDetailView(coordinator: coordinator, playlist: pl)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkImageView(urlString: pl.thumbnailUrl, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fill)
                            Text(pl.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(pl.isLocal ? "Local Playlist" : "Synced Playlist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 150)
        }
    }

    private var albumsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if coordinator.libraryAlbums.isEmpty {
                    // Derive virtual albums from song albumName if album table hasn't been populated
                    let grouped = Dictionary(grouping: coordinator.librarySongs.filter { !($0.albumName ?? "").isEmpty }, by: { $0.albumName ?? "" })
                    ForEach(grouped.keys.sorted(), id: \.self) { albumName in
                        let albumSongs = grouped[albumName] ?? []
                        NavigationLink {
                            AlbumDetailView(coordinator: coordinator, title: albumName, thumbnailURL: albumSongs.first?.thumbnailUrl, songs: albumSongs)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkImageView(urlString: albumSongs.first?.thumbnailUrl, cornerRadius: 10)
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading) {
                                    Text(albumName).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                    Text("\(albumSongs.count) songs").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(MochyTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(coordinator.libraryAlbums, id: \.id) { album in
                        let albumSongs = coordinator.librarySongs.filter { $0.albumId == album.id || $0.albumName == album.title }
                        NavigationLink {
                            AlbumDetailView(coordinator: coordinator, title: album.title, thumbnailURL: album.thumbnailUrl, songs: albumSongs)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkImageView(urlString: album.thumbnailUrl, cornerRadius: 10)
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading) {
                                    Text(album.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                    Text("\(albumSongs.count) songs").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(MochyTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 150)
            }
            .padding(.horizontal, 16)
        }
    }

    private var artistsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(coordinator.libraryArtists, id: \.id) { artist in
                    NavigationLink {
                        ArtistDetailView(coordinator: coordinator, artist: artist)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImageView(urlString: artist.thumbnailUrl, cornerRadius: 24)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                            Text(artist.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(MochyTheme.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 150)
            }
            .padding(.horizontal, 16)
        }
    }

    private func firstLetter(of title: String) -> String {
        guard let ch = title.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first,
              ch.isASCII && ch.isLetter else {
            return "#"
        }
        return String(ch)
    }
}

// MARK: - Playlist Detail View (6 PlaylistStyle Layouts + MixIt Editor + Delete)

public struct PlaylistDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let playlist: PlaylistEntity
    @Environment(\.dismiss) private var dismiss

    @State private var songs: [SongEntity] = []
    @State private var mixPair: (from: SongEntity, to: SongEntity)?
    @State private var showMixSheet = false

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                playlistHeader

                HStack(spacing: 12) {
                    Button {
                        if let first = songs.first {
                            coordinator.playLocalSong(first, allSongs: songs, playlistId: playlist.id)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.defaultAccent)
                    .disabled(songs.isEmpty)

                    Button {
                        let shuf = songs.shuffled()
                        if let first = shuf.first {
                            coordinator.playLocalSong(first, allSongs: shuf, playlistId: playlist.id)
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(songs.isEmpty)
                }

                LazyVStack(spacing: 8) {
                    ForEach(Array(songs.enumerated()), id: \.offset) { idx, song in
                        playlistSongRow(idx: idx, song: song)
                    }
                }

                Spacer(minLength: 140)
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Picker("Playlist Style", selection: $coordinator.settings.playlistStyle) {
                        ForEach(PlaylistStyle.allCases, id: \.self) { st in
                            Text(st.rawValue.capitalized).tag(st)
                        }
                    }
                    Divider()
                    Button("Delete Playlist", role: .destructive) {
                        try? coordinator.database.deletePlaylist(id: playlist.id)
                        coordinator.refreshLocalLibrary()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            songs = (try? coordinator.database.fetchPlaylistSongs(playlistId: playlist.id)) ?? []
        }
        .sheet(isPresented: $showMixSheet) {
            if let mixPair {
                MixItEditorSheet(
                    coordinator: coordinator,
                    playlistId: playlist.id,
                    fromSong: mixPair.from,
                    toSong: mixPair.to
                )
            }
        }
    }

    @ViewBuilder
    private func playlistSongRow(idx: Int, song: SongEntity) -> some View {
        let isCards = coordinator.settings.playlistStyle == .cards
        HStack(spacing: 12) {
            Button {
                coordinator.playLocalSong(song, allSongs: songs, playlistId: playlist.id)
            } label: {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(song.albumName ?? "Track").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if idx + 1 < songs.count {
                Button {
                    mixPair = (song, songs[idx + 1])
                    showMixSheet = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.bold())
                        .foregroundStyle(MochyTheme.defaultAccent)
                        .padding(8)
                        .background(MochyTheme.defaultAccent.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(isCards ? 10 : 4)
        .background(isCards ? MochyTheme.cardSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var playlistHeader: some View {
        let thumb = playlist.thumbnailUrl ?? songs.first?.thumbnailUrl
        switch coordinator.settings.playlistStyle {
        case .editorial, .poster:
            ZStack(alignment: .bottomLeading) {
                ArtworkImageView(urlString: thumb, cornerRadius: 22)
                    .frame(height: 230)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name).font(.title.weight(.black)).foregroundStyle(.white)
                    Text("\(songs.count) tracks · Tap waveform icon for MixIt DJ").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                .padding(16)
            }
        case .minimal:
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.largeTitle.bold()).foregroundStyle(.white)
                Text("\(songs.count) tracks").font(.caption).foregroundStyle(.secondary)
            }
        case .classic, .modern, .cards:
            HStack(spacing: 16) {
                ArtworkImageView(urlString: thumb, cornerRadius: 16)
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                    Text("\(songs.count) tracks").font(.subheadline).foregroundStyle(.secondary)
                    if let desc = playlist.description, !desc.isEmpty {
                        Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Album & Artist Detail Views

public struct AlbumDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let title: String
    public let thumbnailURL: String?
    public let songs: [SongEntity]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ArtworkImageView(urlString: thumbnailURL, cornerRadius: 14)
                        .frame(width: 100, height: 100)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.bold()).foregroundStyle(.white)
                        Text("\(songs.count) tracks").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(songs, id: \.id) { song in
                    Button {
                        coordinator.playLocalSong(song, allSongs: songs)
                    } label: {
                        HStack {
                            Text(song.title).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            if song.duration > 0 {
                                Text(MochyTimeFormatter.format(TimeInterval(song.duration)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 140)
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle(title)
    }
}

public struct ArtistDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let artist: ArtistEntity

    public var body: some View {
        let matchingSongs = coordinator.librarySongs.filter { song in
            let artists = (try? coordinator.database.fetchArtistsForSong(songId: song.id)) ?? []
            return artists.contains(where: { $0.id == artist.id })
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ArtworkImageView(urlString: artist.thumbnailUrl, cornerRadius: 36)
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name).font(.title2.bold()).foregroundStyle(.white)
                        Text("\(matchingSongs.count) songs in library").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(matchingSongs, id: \.id) { song in
                    Button {
                        coordinator.playLocalSong(song, allSongs: matchingSongs)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                                .frame(width: 44, height: 44)
                            Text(song.title).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 140)
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle(artist.name)
    }
}

// MARK: - Non-Destructive SongEditSheet

public struct SongEditSheet: View {
    @Bindable public var coordinator: AppCoordinator
    public let song: SongEntity
    @Environment(\.dismiss) private var dismiss

    @State private var titleText: String = ""
    @State private var artistsText: String = ""
    @State private var albumText: String = ""
    @State private var coverURLText: String = ""
    @State private var noVideo: Bool = false

    public var body: some View {
        NavigationStack {
            Form {
                Section("Non-Destructive Metadata Override") {
                    TextField("Custom Title", text: $titleText)
                    TextField("Custom Artist(s)", text: $artistsText)
                    TextField("Custom Album", text: $albumText)
                    TextField("Custom Cover URL", text: $coverURLText)
                    Toggle("Hide Music Video for this Track", isOn: $noVideo)
                }
            }
            .navigationTitle("Edit Track")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let edit = SongEdit(
                            songId: song.id,
                            title: titleText.isEmpty ? nil : titleText,
                            artists: artistsText.isEmpty ? nil : artistsText,
                            album: albumText.isEmpty ? nil : albumText,
                            cover: coverURLText.isEmpty ? nil : coverURLText,
                            noVideo: noVideo
                        )
                        coordinator.saveSongEdit(edit)
                        dismiss()
                    }
                }
            }
            .onAppear {
                let existing = coordinator.songEditsById[song.id]
                titleText = existing?.title ?? song.title
                artistsText = existing?.artists ?? ""
                albumText = existing?.album ?? song.albumName ?? ""
                coverURLText = existing?.cover ?? song.thumbnailUrl ?? ""
                noVideo = existing?.noVideo ?? false
            }
        }
        .preferredColorScheme(.dark)
    }
}
