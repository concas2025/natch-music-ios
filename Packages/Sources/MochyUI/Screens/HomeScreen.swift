import Combine
import MochyAudio
import MochyCore
import MochyDatabase
import MochyInnerTube
import SwiftUI

private struct HomeHeroItem: Identifiable, Equatable {
    let id: String
    let eyebrow: String
    let title: String
    let artist: String
    let thumbnailURL: String?
    let songEntity: SongEntity?
    let ytTrack: YTTrackItem?
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 1:1 Mochy Home Screen:
/// - Small custom transparent logo top-left morphing into bold `"Home"` on scroll, avatar top-right
/// - Full-bleed auto-cycling Hero Banner (`Continue` / `Recommended` + monochrome Play capsule) fading cleanly on scroll
/// - `Recently Played >`, 3-row numbered `Most Played >` horizontal shelf, `More like [Artist] >`, and Home carousels
public struct HomeScreen: View {
    @Bindable public var coordinator: AppCoordinator

    @State private var showProfileSheet = false
    @State private var scrollOffsetY: CGFloat = 0
    @State private var heroIndex: Int = 0

    private let heroTimer = Timer.publish(every: 6.5, on: .main, in: .common).autoconnect()

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let heroList = heroCandidates
        let activeHero = heroList.isEmpty ? nil : heroList[heroIndex % heroList.count]
        let scrollDown = max(0, -scrollOffsetY)
        let heroOpacity = max(0.0, 1.0 - Double(scrollDown) / 230.0)
        let headerMorph = min(1.0, max(0.0, Double(scrollDown - 85) / 120.0))

        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 26) {
                            Color.clear
                                .frame(height: 0)
                                .id("homeTop")
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: HomeScrollOffsetKey.self,
                                            value: proxy.frame(in: .named("homeScroll")).minY
                                        )
                                    }
                                )

                            if let activeHero {
                                heroBannerSection(
                                    hero: activeHero,
                                    totalCount: heroList.count,
                                    heroOpacity: heroOpacity,
                                    scrollDown: scrollDown
                                )
                            } else {
                                Color.clear.frame(height: 84)
                            }

                            VStack(alignment: .leading, spacing: 26) {
                                recentlyPlayedSection
                                mostPlayedSection
                                moreLikeSection
                                feedCarousels
                                speedDialSection

                                if coordinator.isLoadingHome && coordinator.homeSections.isEmpty {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.white)
                                        Spacer()
                                    }
                                    .padding(.vertical, 36)
                                }
                            }
                            .padding(.horizontal, 16)

                            Spacer(minLength: 160)
                        }
                    }
                    .coordinateSpace(name: "homeScroll")
                    .ignoresSafeArea(edges: .top)
                    .onPreferenceChange(HomeScrollOffsetKey.self) { val in
                        scrollOffsetY = val
                    }
                    .refreshable {
                        coordinator.homeSections = []
                        await coordinator.loadHomeFeedIfNeeded()
                    }
                    .onChange(of: coordinator.scrollToTopTrigger) { _, _ in
                        if coordinator.selectedTab == .home {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                scrollProxy.scrollTo("homeTop", anchor: .top)
                            }
                        }
                    }
                }

                // Pinned Floating Header (Logo -> "Home" morph + Avatar)
                floatingTopHeader(morph: headerMorph)
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .onReceive(heroTimer) { _ in
                guard heroList.count > 1, !coordinator.isPlayerExpanded else { return }
                withAnimation(.easeInOut(duration: 0.7)) {
                    heroIndex = (heroIndex + 1) % heroList.count
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileAndRecapScreen(coordinator: coordinator)
            }
        }
    }

    // MARK: - Pinned Morphing Header

    private func floatingTopHeader(morph: Double) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    NatchLogoImage()
                        .frame(width: 38, height: 38)
                        .opacity(1.0 - morph)
                        .scaleEffect(1.0 - 0.14 * morph)

                    Text("Home")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(morph)
                        .offset(y: CGFloat(1.0 - morph) * 10)
                }
                .frame(height: 40, alignment: .leading)

                Spacer()

                Button {
                    showProfileSheet = true
                } label: {
                    profileAvatarView
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.48 + 0.52 * morph), location: 0.0),
                    .init(color: Color.black.opacity(0.24 + 0.76 * morph), location: 0.65),
                    .init(color: Color.black.opacity(morph), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private var profileAvatarView: some View {
        if let avatarURL = coordinator.profileAvatarURL() {
            ArtworkImageView(urlString: avatarURL.absoluteString, cornerRadius: 17)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 0.8))
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

    // MARK: - Auto-Cycling Full-Bleed Hero Banner

    private func heroBannerSection(
        hero: HomeHeroItem,
        totalCount: Int,
        heroOpacity: Double,
        scrollDown: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImageView(urlString: hero.thumbnailURL, cornerRadius: 0, targetSize: 1080)
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .clipped()
                .id(hero.id)
                .transition(.opacity)
                .offset(y: scrollDown * 0.22)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.36), location: 0.0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.58), location: 0.68),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(hero.eyebrow)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))

                Text("\(hero.title) - \(hero.artist)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Button {
                        playHeroItem(hero)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                            Text("Play")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.72))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if totalCount > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<totalCount, id: \.self) { idx in
                                Capsule()
                                    .fill(Color.white.opacity((heroIndex % totalCount) == idx ? 0.90 : 0.28))
                                    .frame(width: (heroIndex % totalCount) == idx ? 14 : 5, height: 5)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(height: 430)
        .opacity(heroOpacity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { val in
                    guard totalCount > 1 else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        if val.translation.width < -30 {
                            heroIndex = (heroIndex + 1) % totalCount
                        } else if val.translation.width > 30 {
                            heroIndex = (heroIndex - 1 + totalCount) % totalCount
                        }
                    }
                }
        )
    }

    // MARK: - Recently Played Shelf

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        let items = recentDisplayTracks
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Recently Played")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items) { track in
                            Button {
                                coordinator.playTrack(track, queueContext: items)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ArtworkImageView(
                                        urlString: track.thumbnailURL,
                                        cornerRadius: coordinator.settings.thumbnailCornerRadius,
                                        targetSize: 720
                                    )
                                    .frame(width: 152, height: 152)
                                    Text(track.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(track.artistDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.58))
                                        .lineLimit(1)
                                }
                                .frame(width: 152, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Numbered 3-Row Most Played Shelf

    @ViewBuilder
    private var mostPlayedSection: some View {
        let items = mostPlayedDisplayTracks
        if !items.isEmpty {
            let chunked = stride(from: 0, to: items.count, by: 3).map {
                Array(items[$0..<min($0 + 3, items.count)])
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Most Played")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(chunked.enumerated()), id: \.offset) { colIdx, column in
                            VStack(spacing: 12) {
                                ForEach(Array(column.enumerated()), id: \.element.id) { rowIdx, track in
                                    let rank = colIdx * 3 + rowIdx + 1
                                    HStack(spacing: 12) {
                                        Text("\(rank)")
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                            .frame(width: 20, alignment: .leading)

                                        Button {
                                            coordinator.playTrack(track, queueContext: items)
                                        } label: {
                                            HStack(spacing: 12) {
                                                ArtworkImageView(urlString: track.thumbnailURL, cornerRadius: 10)
                                                    .frame(width: 52, height: 52)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(track.title)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Text(track.artistDisplay)
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.58))
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 4)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Menu {
                                            Button {
                                                coordinator.player.playNext(PlaybackItem(ytTrack: track))
                                            } label: {
                                                Label("Play Next", systemImage: "text.insert")
                                            }
                                            Button {
                                                coordinator.player.appendToQueue(PlaybackItem(ytTrack: track))
                                            } label: {
                                                Label("Add to Queue", systemImage: "text.append")
                                            }
                                            Button {
                                                coordinator.toggleLike(songId: track.id)
                                            } label: {
                                                Label(
                                                    coordinator.isLiked(songId: track.id) ? "Unlike" : "Like",
                                                    systemImage: coordinator.isLiked(songId: track.id) ? "heart.slash" : "heart"
                                                )
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white.opacity(0.75))
                                                .frame(width: 30, height: 30)
                                                .background(Color(white: 0.14))
                                                .clipShape(Circle())
                                        }
                                    }
                                    .frame(width: 304)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - More Like [Artist] Shelf

    @ViewBuilder
    private var moreLikeSection: some View {
        let anchor = featuredArtistInfo
        let tracks = coordinator.homeSections.dropFirst().first?.items ?? []
        if let anchor, !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: anchor.thumbnailURL, cornerRadius: 19)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("More like")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                        Text(anchor.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(tracks) { track in
                            Button {
                                coordinator.playTrack(track, queueContext: tracks)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ArtworkImageView(
                                        urlString: track.thumbnailURL,
                                        cornerRadius: coordinator.settings.thumbnailCornerRadius,
                                        targetSize: 720
                                    )
                                    .frame(width: 152, height: 152)
                                    Text(track.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(track.artistDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.58))
                                        .lineLimit(1)
                                }
                                .frame(width: 152, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Remaining Home Feed Carousels & Speed Dial

    @ViewBuilder
    private var feedCarousels: some View {
        ForEach(coordinator.homeSections.dropFirst(2)) { section in
            if !section.items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(section.title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(section.items) { track in
                                Button {
                                    coordinator.playTrack(track, queueContext: section.items)
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        ArtworkImageView(
                                            urlString: track.thumbnailURL,
                                            cornerRadius: coordinator.settings.thumbnailCornerRadius,
                                            targetSize: 720
                                        )
                                        .frame(width: 148, height: 148)
                                        Text(track.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(track.artistDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.58))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 148, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var speedDialSection: some View {
        if !coordinator.speedDialItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Speed Dial")
                let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(coordinator.speedDialItems.prefix(9), id: \.id) { item in
                        Button {
                            let yt = YTTrackItem(
                                id: item.id,
                                title: item.title,
                                artists: [item.subtitle ?? "Unknown"],
                                thumbnailURL: item.thumbnailUrl
                            )
                            coordinator.playTrack(yt)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                ArtworkImageView(urlString: item.thumbnailUrl, cornerRadius: 12)
                                    .aspectRatio(1, contentMode: .fill)
                                LinearGradient(colors: [.clear, .black.opacity(0.84)], startPoint: .center, endPoint: .bottom)
                                Text(item.title)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .padding(7)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers & Derived Shelves

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
    }

    private var heroCandidates: [HomeHeroItem] {
        var result: [HomeHeroItem] = []
        var seenIds = Set<String>()

        if let current = coordinator.player.currentItem {
            seenIds.insert(current.id)
            result.append(
                HomeHeroItem(
                    id: current.id,
                    eyebrow: "Continue",
                    title: current.title,
                    artist: current.artist,
                    thumbnailURL: current.thumbnailURL,
                    songEntity: coordinator.librarySongs.first(where: { $0.id == current.id }),
                    ytTrack: YTTrackItem(
                        id: current.id,
                        title: current.title,
                        artists: [current.artist],
                        album: current.album,
                        durationSeconds: current.durationSeconds,
                        thumbnailURL: current.thumbnailURL
                    )
                )
            )
        } else if let recent = coordinator.recentlyPlayedSongs.first {
            seenIds.insert(recent.id)
            result.append(
                HomeHeroItem(
                    id: recent.id,
                    eyebrow: "Continue",
                    title: recent.title,
                    artist: coordinator.artistDisplay(for: recent),
                    thumbnailURL: recent.thumbnailUrl,
                    songEntity: recent,
                    ytTrack: nil
                )
            )
        }

        let feedTracks = coordinator.homeSections.flatMap(\.items)
        for track in feedTracks where !(track.thumbnailURL ?? "").isEmpty {
            if seenIds.insert(track.id).inserted {
                result.append(
                    HomeHeroItem(
                        id: track.id,
                        eyebrow: "Recommended",
                        title: track.title,
                        artist: track.artistDisplay,
                        thumbnailURL: track.thumbnailURL,
                        songEntity: nil,
                        ytTrack: track
                    )
                )
                if result.count >= 6 { break }
            }
        }
        return result
    }

    private func playHeroItem(_ hero: HomeHeroItem) {
        if coordinator.player.currentItem?.id == hero.id {
            if !coordinator.player.isPlaying {
                coordinator.player.resume()
            } else {
                coordinator.isPlayerExpanded = true
            }
            return
        }
        if let song = hero.songEntity {
            coordinator.playLocalSong(song, allSongs: coordinator.recentlyPlayedSongs.isEmpty ? [song] : coordinator.recentlyPlayedSongs)
        } else if let yt = hero.ytTrack {
            coordinator.playTrack(yt, queueContext: coordinator.homeSections.first?.items)
        }
    }

    private var recentDisplayTracks: [YTTrackItem] {
        if !coordinator.recentlyPlayedSongs.isEmpty {
            return coordinator.recentlyPlayedSongs.map { song in
                YTTrackItem(
                    id: song.id,
                    title: coordinator.songEditsById[song.id]?.title ?? song.title,
                    artists: [coordinator.artistDisplay(for: song)],
                    album: song.albumName,
                    durationSeconds: song.duration > 0 ? song.duration : nil,
                    thumbnailURL: coordinator.songEditsById[song.id]?.cover ?? song.thumbnailUrl
                )
            }
        }
        return Array((coordinator.homeSections.first?.items ?? []).prefix(10))
    }

    private var mostPlayedDisplayTracks: [YTTrackItem] {
        if !coordinator.mostPlayedSongs.isEmpty {
            return coordinator.mostPlayedSongs.prefix(12).map { song in
                YTTrackItem(
                    id: song.id,
                    title: coordinator.songEditsById[song.id]?.title ?? song.title,
                    artists: [coordinator.artistDisplay(for: song)],
                    album: song.albumName,
                    durationSeconds: song.duration > 0 ? song.duration : nil,
                    thumbnailURL: coordinator.songEditsById[song.id]?.cover ?? song.thumbnailUrl
                )
            }
        }
        return Array((coordinator.homeSections.first?.items ?? []).prefix(12))
    }

    private var featuredArtistInfo: (name: String, thumbnailURL: String?)? {
        if let top = coordinator.libraryArtists.first {
            return (top.name, top.thumbnailUrl)
        }
        if let firstTrack = coordinator.homeSections.dropFirst().first?.items.first {
            return (firstTrack.artistDisplay, firstTrack.thumbnailURL)
        }
        return nil
    }
}
