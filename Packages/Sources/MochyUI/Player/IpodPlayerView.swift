import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

private enum IpodScreenRoute: Equatable {
    case menu
    case nowPlaying
    case coverFlow
    case playlists
    case songs
    case chassis
}

/// 1:1 Authentic iPod Classic Player Style:
/// - 4 Chassis Themes (`SILVER`, `BLACK`, `U2` red wheel, `TRUE_DARK`)
/// - Backlit LCD Bezel + `IpodHeader` (Title, Blue Play/Pause Icon, Metallic Battery)
/// - Click-Wheel Navigable Hierarchical Menus + 3D `Cover Flow` with Mirror Reflections
public struct IpodPlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    @State private var route: IpodScreenRoute = .nowPlaying
    @State private var selectedIndex: Int = 0
    @State private var coverFlowIndex: Int = 0
    @State private var lastWheelAngle: Double?
    @State private var accumulatedDelta: Double = 0

    private let rootMenuItems = ["Now Playing", "Cover Flow", "Playlists", "Songs", "Shuffle Songs", "Chassis Theme"]

    public var body: some View {
        let theme = coordinator.settings.ipodTheme

        GeometryReader { geo in
            ZStack {
                chassisBackground(theme)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 74)

                    // Recessed LCD Display
                    lcdScreen
                        .frame(
                            width: min(geo.size.width - 42, 336),
                            height: coordinator.settings.ipodTallScreen ? 276 : 228
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.85), lineWidth: 5)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

                    // Iconic Rotary Click Wheel
                    clickWheel(theme: theme, diameter: min(geo.size.width * 0.64, 248))

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - LCD Display + Header

    private var lcdScreen: some View {
        VStack(spacing: 0) {
            ipodHeader
            Divider().background(.gray.opacity(0.5))

            Group {
                switch route {
                case .menu:
                    ipodMenuList(items: rootMenuItems)
                case .nowPlaying:
                    ipodNowPlayingBody
                case .coverFlow:
                    ipodCoverFlowBody
                case .playlists:
                    ipodMenuList(items: coordinator.libraryPlaylists.isEmpty ? ["No Playlists Yet"] : coordinator.libraryPlaylists.map(\.name))
                case .songs:
                    ipodMenuList(items: coordinator.librarySongs.isEmpty ? ["No Library Songs"] : coordinator.librarySongs.prefix(40).map(\.title))
                case .chassis:
                    ipodMenuList(items: IpodTheme.allCases.map { $0.rawValue.replacingOccurrences(of: "_", with: " ") })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.96))
        }
    }

    private var ipodHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: coordinator.player.isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.14, green: 0.45, blue: 0.92))

            Text(headerTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)

            Spacer()

            // Classic glossy green battery icon
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.black.opacity(0.65), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(colors: [Color(red: 0.48, green: 0.88, blue: 0.32), Color(red: 0.18, green: 0.66, blue: 0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 17, height: 7)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            LinearGradient(
                colors: [Color(white: 0.94), Color(white: 0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerTitle: String {
        switch route {
        case .menu: return "Natch iPod"
        case .nowPlaying: return "Now Playing"
        case .coverFlow: return "Cover Flow"
        case .playlists: return "Playlists"
        case .songs: return "Songs"
        case .chassis: return "Chassis Theme"
        }
    }

    private func ipodMenuList(items: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, title in
                        let isSel = idx == selectedIndex
                        HStack {
                            Text(title)
                                .font(.system(size: 13, weight: isSel ? .bold : .medium))
                                .foregroundStyle(isSel ? .white : .black)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isSel ? .white : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isSel
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.24, green: 0.56, blue: 0.96), Color(red: 0.10, green: 0.38, blue: 0.85)], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color.clear)
                        )
                        .id(idx)
                        .onTapGesture {
                            selectedIndex = idx
                            handleCenterSelect()
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newVal in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
    }

    private var ipodNowPlayingBody: some View {
        let item = coordinator.player.currentItem
        let duration = max(coordinator.player.duration, 1.0)
        let pct = min(1, max(0, coordinator.player.currentTime / duration))

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: 4)
                    .frame(width: 96, height: 96)
                    .rotation3DEffect(.degrees(8), axis: (x: 0, y: 1, z: 0))
                    .shadow(color: .black.opacity(0.28), radius: 5, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item?.title ?? "No Track")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                    Text(item?.artist ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.68))
                        .lineLimit(1)
                    if let album = item?.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text("\(coordinator.player.currentIndex + 1) of \(max(1, coordinator.player.queue.count))")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.gray)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer(minLength: 4)

            // Glossy Aqua Progress Bar
            VStack(spacing: 4) {
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.85))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(red: 0.34, green: 0.68, blue: 0.99), Color(red: 0.12, green: 0.44, blue: 0.88)], startPoint: .top, endPoint: .bottom))
                            .frame(width: barGeo.size.width * pct)
                    }
                }
                .frame(height: 9)

                HStack {
                    Text(MochyTimeFormatter.format(coordinator.player.currentTime))
                    Spacer()
                    Text("-\(MochyTimeFormatter.format(max(0, duration - coordinator.player.currentTime)))")
                }
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.black.opacity(0.70))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var ipodCoverFlowBody: some View {
        let items: [(title: String, artist: String, thumb: String?)] = coordinator.player.queue.isEmpty
            ? coordinator.librarySongs.prefix(20).map { ($0.title, $0.albumName ?? "Library", $0.thumbnailUrl) }
            : coordinator.player.queue.map { ($0.title, $0.artist, $0.thumbnailURL) }
        let safeIdx = items.isEmpty ? 0 : max(0, min(coverFlowIndex, items.count - 1))

        return ZStack {
            LinearGradient(colors: [.black, Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom)

            if items.isEmpty {
                Text("Queue or Library Empty")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 8) {
                    ZStack {
                        ForEach(max(0, safeIdx - 2)...min(items.count - 1, safeIdx + 2), id: \.self) { idx in
                            let offset = idx - safeIdx
                            let angle: Double = offset == 0 ? 0 : (offset < 0 ? 52 : -52)
                            VStack(spacing: 0) {
                                ArtworkImageView(urlString: items[idx].thumb, cornerRadius: 4)
                                    .frame(width: 92, height: 92)
                                // Classic CoverReflection mirror below cover
                                ArtworkImageView(urlString: items[idx].thumb, cornerRadius: 4)
                                    .frame(width: 92, height: 28)
                                    .scaleEffect(y: -1)
                                    .opacity(0.26)
                                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                            }
                            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
                            .scaleEffect(offset == 0 ? 1.05 : 0.78)
                            .offset(x: CGFloat(offset) * 62)
                            .zIndex(offset == 0 ? 10 : Double(5 - abs(offset)))
                        }
                    }
                    .animation(.spring(response: 0.30, dampingFraction: 0.80), value: safeIdx)

                    VStack(spacing: 1) {
                        Text(items[safeIdx].title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(items[safeIdx].artist)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    // MARK: - Rotary Click Wheel

    private func clickWheel(theme: IpodTheme, diameter: CGFloat) -> some View {
        let wheelColor = clickWheelFill(theme)
        let labelColor = clickWheelLabel(theme)
        let centerColor = centerButtonFill(theme)

        return ZStack {
            Circle()
                .fill(wheelColor)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { val in
                            let cx = diameter * 0.5
                            let cy = diameter * 0.5
                            let angle = atan2(val.location.y - cy, val.location.x - cx)
                            if let prev = lastWheelAngle {
                                var delta = angle - prev
                                if delta > .pi { delta -= 2 * .pi }
                                if delta < -.pi { delta += 2 * .pi }
                                accumulatedDelta += delta
                                let stepRad = 0.42 // ~24 degrees per click
                                if abs(accumulatedDelta) >= stepRad {
                                    let dir = accumulatedDelta > 0 ? 1 : -1
                                    accumulatedDelta = 0
                                    handleWheelTick(direction: dir)
                                }
                            }
                            lastWheelAngle = angle
                        }
                        .onEnded { _ in
                            lastWheelAngle = nil
                            accumulatedDelta = 0
                        }
                )

            // 4 cardinal buttons
            VStack {
                Button("MENU") {
                    if route == .menu {
                        route = .nowPlaying
                    } else {
                        route = .menu
                        selectedIndex = 0
                    }
                    fireClickTick()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(labelColor)
                .padding(.top, 16)

                Spacer()

                HStack {
                    Button {
                        coordinator.player.skipPrevious()
                        fireClickTick()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(labelColor)
                    }
                    .padding(.leading, 18)

                    Spacer()

                    Button {
                        coordinator.player.skipNext()
                        fireClickTick()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(labelColor)
                    }
                    .padding(.trailing, 18)
                }

                Spacer()

                Button {
                    coordinator.player.togglePlayPause()
                    fireClickTick()
                } label: {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(labelColor)
                }
                .padding(.bottom, 16)
            }
            .frame(width: diameter, height: diameter)
            .buttonStyle(.plain)

            // Center Select Button
            Button {
                handleCenterSelect()
                fireClickTick()
            } label: {
                Circle()
                    .fill(centerColor)
                    .frame(width: diameter * 0.35, height: diameter * 0.35)
                    .overlay(Circle().strokeBorder(.black.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func handleWheelTick(direction: Int) {
        fireClickTick()
        switch route {
        case .nowPlaying:
            coordinator.player.seek(to: coordinator.player.currentTime + Double(direction) * 4.0)
        case .coverFlow:
            let count = max(1, coordinator.player.queue.isEmpty ? coordinator.librarySongs.prefix(20).count : coordinator.player.queue.count)
            coverFlowIndex = max(0, min(count - 1, coverFlowIndex + direction))
        case .menu:
            selectedIndex = max(0, min(rootMenuItems.count - 1, selectedIndex + direction))
        case .playlists:
            let count = max(1, coordinator.libraryPlaylists.count)
            selectedIndex = max(0, min(count - 1, selectedIndex + direction))
        case .songs:
            let count = max(1, min(40, coordinator.librarySongs.count))
            selectedIndex = max(0, min(count - 1, selectedIndex + direction))
        case .chassis:
            selectedIndex = max(0, min(IpodTheme.allCases.count - 1, selectedIndex + direction))
        }
    }

    private func handleCenterSelect() {
        switch route {
        case .nowPlaying:
            route = .coverFlow
            coverFlowIndex = coordinator.player.currentIndex
        case .coverFlow:
            if coordinator.player.queue.indices.contains(coverFlowIndex) {
                coordinator.player.jumpToQueueIndex(coverFlowIndex)
            } else if coordinator.librarySongs.indices.contains(coverFlowIndex) {
                coordinator.playLocalSong(coordinator.librarySongs[coverFlowIndex], allSongs: coordinator.librarySongs)
            }
            route = .nowPlaying
        case .menu:
            switch selectedIndex {
            case 0: route = .nowPlaying
            case 1:
                route = .coverFlow
                coverFlowIndex = coordinator.player.currentIndex
            case 2:
                route = .playlists
                selectedIndex = 0
            case 3:
                route = .songs
                selectedIndex = 0
            case 4:
                if !coordinator.librarySongs.isEmpty {
                    let shuffled = coordinator.librarySongs.shuffled()
                    coordinator.playLocalSong(shuffled[0], allSongs: shuffled)
                    route = .nowPlaying
                }
            case 5:
                route = .chassis
                selectedIndex = IpodTheme.allCases.firstIndex(of: coordinator.settings.ipodTheme) ?? 0
            default: break
            }
        case .playlists:
            if coordinator.libraryPlaylists.indices.contains(selectedIndex) {
                let pl = coordinator.libraryPlaylists[selectedIndex]
                let songs = (try? coordinator.database.fetchPlaylistSongs(playlistId: pl.id)) ?? []
                if let first = songs.first {
                    coordinator.playLocalSong(first, allSongs: songs, playlistId: pl.id)
                    route = .nowPlaying
                }
            }
        case .songs:
            if coordinator.librarySongs.indices.contains(selectedIndex) {
                coordinator.playLocalSong(coordinator.librarySongs[selectedIndex], allSongs: coordinator.librarySongs)
                route = .nowPlaying
            }
        case .chassis:
            if IpodTheme.allCases.indices.contains(selectedIndex) {
                coordinator.settings.ipodTheme = IpodTheme.allCases[selectedIndex]
                route = .menu
                selectedIndex = 0
            }
        }
    }

    private func fireClickTick() {
        #if os(iOS) && canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func chassisBackground(_ theme: IpodTheme) -> LinearGradient {
        switch theme {
        case .silver:
            return LinearGradient(colors: [Color(white: 0.86), Color(white: 0.72), Color(white: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .black:
            return LinearGradient(colors: [Color(white: 0.18), Color(white: 0.08), Color(white: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .u2:
            return LinearGradient(colors: [Color(white: 0.10), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
        case .trueDark:
            return LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
        }
    }

    private func clickWheelFill(_ theme: IpodTheme) -> Color {
        switch theme {
        case .silver: return Color(white: 0.96)
        case .black: return Color(white: 0.15)
        case .u2: return Color(red: 0.80, green: 0.08, blue: 0.12)
        case .trueDark: return Color(white: 0.08)
        }
    }

    private func clickWheelLabel(_ theme: IpodTheme) -> Color {
        theme == .silver ? Color(white: 0.45) : Color.white.opacity(0.86)
    }

    private func centerButtonFill(_ theme: IpodTheme) -> Color {
        switch theme {
        case .silver: return Color(white: 0.78)
        case .black: return Color(white: 0.11)
        case .u2: return Color(white: 0.09)
        case .trueDark: return Color.black
        }
    }
}
