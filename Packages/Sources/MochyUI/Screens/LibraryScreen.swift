import MochyAudio
import MochyCore
import MochyDatabase
import MochySync
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum LibraryHubFilter: String, CaseIterable, Sendable {
    case all = "All"
    case localAndDownloaded = "Local & downloaded"
    case cached = "Cached"
    case history = "History"
    case genres = "Genres"
    case imported = "Imported"
}

/// 1:1 Mochy Library Bento Hub:
/// - Clean `"Library"` header + circular avatar
/// - `"Search your library"` capsule filter bar
/// - Wrapped monochrome filter chips (`All`, `Local & downloaded`, `Cached`, `History`, `Genres`, `Imported`)
/// - Dismissible `"Import your music here!"` hero card with continuous scrolling app icon marquee
/// - 2-column Bento grid (`Songs`, `Playlists`, `Albums`, `Artists`) + full-width `Recently added` & `Liked` cards
/// - Full detail views with A–Z `IndexGlideRail`, non-destructive `SongEditSheet`, 6-style `PlaylistDetailView`, & `MixItEditorSheet`
public struct LibraryScreen: View {
    @Bindable public var coordinator: AppCoordinator

    @AppStorage("dismissedImportBanner") private var dismissedImportBanner = false
    @State private var selectedFilter: LibraryHubFilter = .all
    @State private var libraryQuery: String = ""
    @State private var showProfileSheet = false
    @State private var showImportSheet = false
    @State private var showLocalFileImporter = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var editingSong: SongEntity?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: 1).id("libraryTop")

                        // Header: "Library" + Circular Avatar
                        HStack {
                            Text("Library")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                showProfileSheet = true
                            } label: {
                                profileAvatarView
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)

                        // Dark Pill Search Bar ("Search your library")
                        HStack(spacing: 10) {
                            TextField("Search your library", text: $libraryQuery)
                                .foregroundStyle(.white)
                            if !libraryQuery.isEmpty {
                                Button {
                                    libraryQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(Color(white: 0.095))
                        .clipShape(Capsule())

                        // Wrapped Filter Chips (2 compact rows matching real Mochy screenshots)
                        MochyChipFlowLayout(spacing: 8) {
                            ForEach(LibraryHubFilter.allCases, id: \.self) { chip in
                                let selected = selectedFilter == chip
                                Button {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        selectedFilter = chip
                                    }
                                } label: {
                                    Text(chip.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 9)
                                        .background(selected ? MochyTheme.chipActiveSurface : Color(white: 0.095))
                                        .foregroundStyle(selected ? .white : .white.opacity(0.78))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            searchResultsSection
                        } else {
                            filterContent
                        }

                        Spacer(minLength: 160)
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: coordinator.scrollToTopTrigger) { _, _ in
                    if coordinator.selectedTab == .library {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            scrollProxy.scrollTo("libraryTop", anchor: .top)
                        }
                    }
                }
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .sheet(isPresented: $showProfileSheet) {
                ProfileAndRecapScreen(coordinator: coordinator)
            }
            .sheet(isPresented: $showImportSheet) {
                LibraryImportSheet(coordinator: coordinator, onOpenLocalPicker: {
                    showImportSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showLocalFileImporter = true
                    }
                })
            }
            .sheet(item: $editingSong) { song in
                SongEditSheet(coordinator: coordinator, song: song)
            }
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
            .task {
                await coordinator.refreshDownloadedState()
            }
        }
    }

    @ViewBuilder
    private var profileAvatarView: some View {
        if let avatarURL = coordinator.profileAvatarURL() {
            ArtworkImageView(urlString: avatarURL.absoluteString, cornerRadius: 17)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        } else {
            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                )
        }
    }

    // MARK: - Main Filter Router

    @ViewBuilder
    private var filterContent: some View {
        switch selectedFilter {
        case .all:
            bentoHubContent
        case .localAndDownloaded:
            localAndDownloadedContent
        case .cached:
            let cached = coordinator.librarySongs.filter { coordinator.downloadedSongIds.contains($0.id) }
            songsInlineList(cached, emptyText: "No cached tracks yet. Play songs to cache them offline.")
        case .history:
            songsInlineList(coordinator.recentlyPlayedSongs, emptyText: "Your listening history will appear here.")
        case .genres:
            genresContent
        case .imported:
            importedPlaylistsContent
        }
    }

    // MARK: - Bento Hub (1:1 Images 5 & 6)

    @ViewBuilder
    private var bentoHubContent: some View {
        if !dismissedImportBanner {
            importHeroCard
        }

        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let recentSorted = coordinator.librarySongs.sorted {
            ($0.inLibrary ?? $0.dateModified ?? 0) > ($1.inLibrary ?? $1.dateModified ?? 0)
        }
        let likedSongs = coordinator.librarySongs.filter(\.liked)
        let albumsCount = effectiveAlbumGroups.count

        LazyVGrid(columns: cols, spacing: 12) {
            NavigationLink {
                LibrarySongsDetailView(
                    coordinator: coordinator,
                    title: "Songs",
                    songs: coordinator.librarySongs,
                    showLocalImport: true,
                    editingSong: $editingSong
                )
            } label: {
                bentoCard(
                    title: "Songs",
                    count: coordinator.librarySongs.count,
                    previewURL: coordinator.recentlyPlayedSongs.first?.thumbnailUrl ?? coordinator.librarySongs.first?.thumbnailUrl,
                    style: .tiltedArt
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                LibraryPlaylistsDetailView(coordinator: coordinator)
            } label: {
                bentoCard(
                    title: "Playlists",
                    count: coordinator.libraryPlaylists.count,
                    previewURL: coordinator.libraryPlaylists.first?.thumbnailUrl,
                    style: .tiltedArt
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                LibraryAlbumsDetailView(coordinator: coordinator, groups: effectiveAlbumGroups)
            } label: {
                bentoCard(
                    title: "Albums",
                    count: albumsCount,
                    previewURL: effectiveAlbumGroups.first?.thumbnailURL,
                    style: .tiltedArt
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                LibraryArtistsDetailView(coordinator: coordinator)
            } label: {
                bentoCard(
                    title: "Artists",
                    count: coordinator.libraryArtists.count,
                    previewURL: nil,
                    style: .artistsPair(
                        coordinator.libraryArtists.first?.thumbnailUrl,
                        coordinator.libraryArtists.dropFirst().first?.thumbnailUrl
                    )
                )
            }
            .buttonStyle(.plain)
        }

        NavigationLink {
            LibrarySongsDetailView(
                coordinator: coordinator,
                title: "Recently added",
                songs: recentSorted,
                showLocalImport: false,
                editingSong: $editingSong
            )
        } label: {
            bentoCard(
                title: "Recently added",
                count: coordinator.librarySongs.count,
                previewURL: recentSorted.first?.thumbnailUrl,
                style: .tiltedArt
            )
        }
        .buttonStyle(.plain)

        NavigationLink {
            LibrarySongsDetailView(
                coordinator: coordinator,
                title: "Liked",
                songs: likedSongs,
                showLocalImport: false,
                editingSong: $editingSong
            )
        } label: {
            bentoCard(
                title: "Liked",
                count: likedSongs.count,
                previewURL: likedSongs.first?.thumbnailUrl,
                style: .likedWithBadge
            )
        }
        .buttonStyle(.plain)
    }

    private enum BentoArtStyle {
        case tiltedArt
        case artistsPair(String?, String?)
        case likedWithBadge
    }

    private func bentoCard(title: String, count: Int, previewURL: String?, style: BentoArtStyle) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)

            switch style {
            case .tiltedArt:
                if let previewURL {
                    ArtworkImageView(urlString: previewURL, cornerRadius: 12, targetSize: 360)
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-8))
                        .offset(x: 4, y: 12)
                }
            case let .artistsPair(url1, url2):
                if url1 != nil || url2 != nil {
                    HStack(spacing: -14) {
                        if let url1 {
                            ArtworkImageView(urlString: url1, cornerRadius: 24, targetSize: 240)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        }
                        if let url2 {
                            ArtworkImageView(urlString: url2, cornerRadius: 24, targetSize: 240)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color(white: 0.08), lineWidth: 2))
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
                }
            case .likedWithBadge:
                HStack(spacing: -12) {
                    if let previewURL {
                        ArtworkImageView(urlString: previewURL, cornerRadius: 12, targetSize: 360)
                            .frame(width: 66, height: 66)
                            .rotationEffect(.degrees(-8))
                            .offset(y: 10)
                    }
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.16))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "heart")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.88))
                        )
                        .offset(x: 4, y: 10)
                }
            }
        }
        .frame(height: 114)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Dismissible "Import your music here!" Card with Marquee

    private var importHeroCard: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showImportSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    ServiceIconsMarquee()
                        .frame(height: 64)
                        .padding(.top, 16)

                    Text("Import your music here!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.075))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    dismissedImportBanner = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .padding(12)
        }
    }

    // MARK: - Secondary Filter Chip Views

    private var localAndDownloadedContent: some View {
        let filtered = coordinator.librarySongs.filter {
            $0.isLocal || coordinator.downloadedSongIds.contains($0.id)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    showLocalFileImporter = true
                } label: {
                    Label("Import Audio Files", systemImage: "folder.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(MochyTheme.buttonFill)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(white: 0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            songsInlineList(filtered, emptyText: "No local or downloaded tracks yet.")
        }
    }

    private var genresContent: some View {
        let grouped = Dictionary(grouping: coordinator.librarySongs) { song in
            let g = (song.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return g.isEmpty ? "All Library Tracks" : g
        }
        return LazyVStack(spacing: 10) {
            ForEach(grouped.keys.sorted(), id: \.self) { genre in
                let songs = grouped[genre] ?? []
                NavigationLink {
                    LibrarySongsDetailView(
                        coordinator: coordinator,
                        title: genre,
                        songs: songs,
                        showLocalImport: false,
                        editingSong: $editingSong
                    )
                } label: {
                    HStack(spacing: 12) {
                        ArtworkImageView(urlString: songs.first?.thumbnailUrl, cornerRadius: 10)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(genre).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            Text("\(songs.count) tracks").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var importedPlaylistsContent: some View {
        let imported = coordinator.libraryPlaylists.filter { coordinator.importedPlaylistIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                showImportSheet = true
            } label: {
                Label("Import Playlist from URL or CSV", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(MochyTheme.buttonFill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if imported.isEmpty {
                Text("No imported playlists yet. Tap above to import from Spotify, Apple Music, or YouTube Music.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(imported, id: \.id) { pl in
                        NavigationLink {
                            PlaylistDetailView(coordinator: coordinator, playlist: pl)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkImageView(urlString: pl.thumbnailUrl, cornerRadius: 14)
                                    .aspectRatio(1, contentMode: .fill)
                                Text(pl.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                Text("Imported playlist").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        let q = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchedSongs = coordinator.librarySongs.filter {
            $0.title.lowercased().contains(q)
                || coordinator.artistDisplay(for: $0).lowercased().contains(q)
                || ($0.albumName?.lowercased().contains(q) ?? false)
        }
        let matchedPlaylists = coordinator.libraryPlaylists.filter {
            $0.name.lowercased().contains(q)
        }

        return VStack(alignment: .leading, spacing: 14) {
            if !matchedPlaylists.isEmpty {
                Text("Playlists").font(.headline).foregroundStyle(.white)
                ForEach(matchedPlaylists, id: \.id) { pl in
                    NavigationLink {
                        PlaylistDetailView(coordinator: coordinator, playlist: pl)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImageView(urlString: pl.thumbnailUrl, cornerRadius: 10)
                                .frame(width: 48, height: 48)
                            Text(pl.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Songs").font(.headline).foregroundStyle(.white)
            songsInlineList(matchedSongs, emptyText: "No matches for \"\(libraryQuery)\".")
        }
    }

    private func songsInlineList(_ songs: [SongEntity], emptyText: String) -> some View {
        LazyVStack(spacing: 6) {
            if songs.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)
            } else {
                ForEach(songs, id: \.id) { song in
                    LibrarySongRowView(
                        coordinator: coordinator,
                        song: song,
                        context: songs,
                        onEdit: { editingSong = song }
                    )
                }
            }
        }
    }

    private var effectiveAlbumGroups: [LibraryAlbumGroup] {
        if !coordinator.libraryAlbums.isEmpty {
            return coordinator.libraryAlbums.map { album in
                let songs = coordinator.librarySongs.filter { $0.albumId == album.id || $0.albumName == album.title }
                return LibraryAlbumGroup(
                    id: album.id,
                    title: album.title,
                    thumbnailURL: album.thumbnailUrl ?? songs.first?.thumbnailUrl,
                    songs: songs
                )
            }
        }
        let grouped = Dictionary(
            grouping: coordinator.librarySongs.filter { !($0.albumName ?? "").trimmingCharacters(in: .whitespaces).isEmpty },
            by: { $0.albumName ?? "" }
        )
        return grouped.keys.sorted().map { name in
            let songs = grouped[name] ?? []
            return LibraryAlbumGroup(
                id: name,
                title: name,
                thumbnailURL: songs.first?.thumbnailUrl,
                songs: songs
            )
        }
    }
}

public struct LibraryAlbumGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let thumbnailURL: String?
    public let songs: [SongEntity]

    public init(id: String, title: String, thumbnailURL: String?, songs: [SongEntity]) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.songs = songs
    }
}

// MARK: - Wrapped Monochrome Chip Layout

private struct MochyChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 340
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Scrolling Service Icons Marquee ("Import your music here!")

private struct ServiceIconsMarquee: View {
    private let tileStep: CGFloat = 72
    private let countPerCycle = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let cycleWidth = tileStep * CGFloat(countPerCycle)
            let raw = timeline.date.timeIntervalSinceReferenceDate * 22.0
            let shift = -CGFloat(raw.truncatingRemainder(dividingBy: Double(cycleWidth)))

            HStack(spacing: 16) {
                ForEach(0..<12, id: \.self) { idx in
                    serviceTile(kind: idx % 4)
                }
            }
            .offset(x: shift)
        }
        .clipped()
    }

    @ViewBuilder
    private func serviceTile(kind: Int) -> some View {
        switch kind {
        case 0: // Tidal-style black diamond cluster
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black)
                .frame(width: 56, height: 56)
                .overlay(
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            diamond
                            diamond
                            diamond
                        }
                        diamond
                    }
                )
        case 1: // YouTube Music-style red play circle badge
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.96, green: 0.04, blue: 0.08))
                .frame(width: 56, height: 56)
                .overlay(
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                            .frame(width: 30, height: 30)
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                )
        case 2: // Spotify-style green circle badge
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.04))
                .frame(width: 56, height: 56)
                .overlay(
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                            .frame(width: 38, height: 38)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.black)
                    }
                )
        default: // Apple Music-style coral note tile
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.99, green: 0.34, blue: 0.44), Color(red: 0.96, green: 0.18, blue: 0.32)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                )
        }
    }

    private var diamond: some View {
        Rectangle()
            .fill(.white)
            .frame(width: 7, height: 7)
            .rotationEffect(.degrees(45))
    }
}

// MARK: - Library Import Sheet (URL + CSV + Local Audio)

public struct LibraryImportSheet: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenLocalPicker: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var showCSVImporter = false

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import Public Playlist URL")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Supports Spotify, Apple Music, Tidal, and YouTube Music playlists without login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Paste playlist URL...", text: $urlText)
                        .padding(12)
                        .background(MochyTheme.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)

                    Button {
                        Task { await coordinator.runPlaylistImport(urlString: urlText) }
                    } label: {
                        Text("Import Playlist")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.buttonFill)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isImportingPlaylist)
                }

                if coordinator.isImportingPlaylist, let prog = coordinator.importProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        if prog.totalCount > 0 {
                            ProgressView(value: Double(prog.matchedCount), total: Double(prog.totalCount))
                                .tint(.white)
                        } else {
                            ProgressView().tint(.white)
                        }
                        Text("\(prog.stage) (\(prog.matchedCount)/\(prog.totalCount))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if let msg = coordinator.importStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        showCSVImporter = true
                    } label: {
                        Label("Import CSV File (Exportify / TuneMyMusic)", systemImage: "doc.plaintext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.isImportingPlaylist)

                    Button {
                        onOpenLocalPicker()
                    } label: {
                        Label("Import Local Audio Files (MP3 / FLAC / M4A)", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(18)
            .background(Color.black)
            .navigationTitle("Import Music")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        let name = url.deletingPathExtension().lastPathComponent
                        Task { await coordinator.runCSVImport(csvText: text, playlistName: name) }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Bento Detail Screens (Songs w/ GlideRail, Playlists, Albums, Artists)

public struct LibrarySongsDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let title: String
    public let songs: [SongEntity]
    public let showLocalImport: Bool
    @Binding public var editingSong: SongEntity?

    @State private var activeGlideLetter: String?
    @State private var showLocalFileImporter = false
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)

    public var body: some View {
        let sorted = title == "Recently added"
            ? songs
            : songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        if sorted.isEmpty {
                            Text("No tracks here yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 48)
                        } else {
                            ForEach(sorted, id: \.id) { song in
                                LibrarySongRowView(
                                    coordinator: coordinator,
                                    song: song,
                                    context: sorted,
                                    onEdit: { editingSong = song }
                                )
                                .id(song.id)
                            }
                        }
                        Spacer(minLength: 150)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 28)
                    .padding(.top, 10)
                }
                .onChange(of: activeGlideLetter) { _, letter in
                    guard let letter else { return }
                    if let target = sorted.first(where: { firstLetter(of: $0.title) == letter }) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }

            if sorted.count >= 6 {
                GeometryReader { railGeo in
                    VStack(spacing: 1) {
                        ForEach(alphabet, id: \.self) { ch in
                            Text(ch)
                                .font(.system(size: 9, weight: activeGlideLetter == ch ? .black : .semibold))
                                .foregroundStyle(activeGlideLetter == ch ? .white : .white.opacity(0.42))
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
        .background(Color.black)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showLocalImport {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showLocalFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showLocalFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                coordinator.importLocalAudio(urls: urls)
            }
        }
    }

    private func firstLetter(of text: String) -> String {
        guard let ch = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first,
              ch.isASCII && ch.isLetter else {
            return "#"
        }
        return String(ch)
    }
}

public struct LibrarySongRowView: View {
    @Bindable public var coordinator: AppCoordinator
    public let song: SongEntity
    public let context: [SongEntity]
    public let onEdit: () -> Void

    public var body: some View {
        let edit = coordinator.songEditsById[song.id]
        let displayTitle = edit?.title ?? song.title
        let displayCover = edit?.cover ?? song.thumbnailUrl
        let displayArtist = coordinator.artistDisplay(for: song)

        HStack(spacing: 12) {
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
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.14))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                            if coordinator.downloadedSongIds.contains(song.id) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Text(displayArtist)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.60))
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
                Button(action: onEdit) {
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
                    .foregroundStyle(.white.opacity(0.60))
                    .frame(width: 28, height: 32)
            }
        }
        .padding(.vertical, 4)
    }
}

public struct LibraryPlaylistsDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    public var body: some View {
        ScrollView(showsIndicators: false) {
            if coordinator.libraryPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Text("No playlists yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("Create Playlist") {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.buttonFill)
                }
                .padding(.top, 60)
            } else {
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
        .background(Color.black)
        .navigationTitle("Playlists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Create Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") { coordinator.createPlaylist(name: newPlaylistName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

public struct LibraryAlbumsDetailView: View {
    @Bindable public var coordinator: AppCoordinator
    public let groups: [LibraryAlbumGroup]

    public init(coordinator: AppCoordinator, groups: [LibraryAlbumGroup]) {
        self.coordinator = coordinator
        self.groups = groups
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if groups.isEmpty {
                    Text("No albums in your library yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 48)
                } else {
                    ForEach(groups) { group in
                        NavigationLink {
                            AlbumDetailView(
                                coordinator: coordinator,
                                title: group.title,
                                thumbnailURL: group.thumbnailURL,
                                songs: group.songs
                            )
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkImageView(urlString: group.thumbnailURL, cornerRadius: 10)
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading) {
                                    Text(group.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                    Text("\(group.songs.count) songs").font(.caption).foregroundStyle(.secondary)
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
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Albums")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

public struct LibraryArtistsDetailView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if coordinator.libraryArtists.isEmpty {
                    Text("No artists in your library yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 48)
                } else {
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
                }
                Spacer(minLength: 150)
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Artists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                    .tint(MochyTheme.buttonFill)
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
                        Text(coordinator.artistDisplay(for: song)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.14))
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
