import MochyAudio
import MochyCore
import MochyDatabase
import MochyInnerTube
import SwiftUI

/// 1:1 Mochy Home Screen supporting `MOCHYY`, `LISTEN_NOW`, and `HOP_IN` layouts:
/// - Avatar button opening `ProfileAndRecapScreen` (3D ID Card + Scratch Barcode + Recap)
/// - Speed Dial 3-column pinned grid
/// - Quick Picks 4-row horizontal paging shelf
/// - YouTube Music dynamic carousels
/// - Pull-to-refresh & re-tap `scrollToTopTrigger`
public struct HomeScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var showProfileSheet = false

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 1).id("homeTop")

                        // Top Greeting + Avatar Profile Button + HomeStyle Switcher
                        topHeaderBar

                        // Layout variations matching Mochy's 3 HomeStyle modes
                        switch coordinator.settings.homeStyle {
                        case .mochyy:
                            recapTeaserBanner
                            speedDialSection
                            quickPicksShelf
                            feedCarousels
                        case .listenNow:
                            quickPicksShelf
                            feedCarousels
                            speedDialSection
                            recapTeaserBanner
                        case .hopIn:
                            speedDialSection
                            recapTeaserBanner
                            feedCarousels
                            quickPicksShelf
                        }

                        if coordinator.isLoadingHome && coordinator.homeSections.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("Loading Natch feed...")
                                    .tint(.white)
                                Spacer()
                            }
                            .padding(.vertical, 40)
                        }

                        Spacer(minLength: 150)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
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
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .sheet(isPresented: $showProfileSheet) {
                ProfileAndRecapScreen(coordinator: coordinator)
            }
        }
    }

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Natch Music")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)
                let name = coordinator.settings.profileUsername
                Text(name.isEmpty ? "Hi-Res · Mochy Core" : "Welcome back, \(name)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Menu {
                ForEach(HomeStyle.allCases, id: \.self) { style in
                    Button {
                        coordinator.settings.homeStyle = style
                    } label: {
                        HStack {
                            Text(style.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            if coordinator.settings.homeStyle == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(MochyTheme.cardSurface)
                    .clipShape(Circle())
            }

            Button {
                showProfileSheet = true
            } label: {
                if let avatarURL = coordinator.profileAvatarURL() {
                    ArtworkImageView(urlString: avatarURL.absoluteString, cornerRadius: 20)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(MochyTheme.defaultAccent, lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [MochyTheme.defaultAccent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.white))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var recapTeaserBanner: some View {
        Button {
            showProfileSheet = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(MochyTheme.defaultAccent.opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ID Card · USR#\(coordinator.settings.profileCardNumber)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Flip & scratch barcode to unlock your Listening Recap")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color(white: 0.14), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var speedDialSection: some View {
        if !coordinator.speedDialItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Speed Dial").font(.title3.bold()).foregroundStyle(.white)
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
                                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
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

    @ViewBuilder
    private var quickPicksShelf: some View {
        if let firstSection = coordinator.homeSections.first, !firstSection.items.isEmpty {
            let chunked = stride(from: 0, to: firstSection.items.count, by: 4).map {
                Array(firstSection.items[$0..<min($0 + 4, firstSection.items.count)])
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(firstSection.title.isEmpty ? "Quick Picks" : firstSection.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(chunked.enumerated()), id: \.offset) { _, column in
                            VStack(spacing: 10) {
                                ForEach(column) { track in
                                    Button {
                                        coordinator.playTrack(track, queueContext: firstSection.items)
                                    } label: {
                                        HStack(spacing: 10) {
                                            ArtworkImageView(urlString: track.thumbnailURL, cornerRadius: 8)
                                                .frame(width: 50, height: 50)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(track.artistDisplay)
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.65))
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 4)
                                            Button {
                                                coordinator.player.playNext(PlaybackItem(ytTrack: track))
                                            } label: {
                                                Image(systemName: "text.insert")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.55))
                                            }
                                        }
                                        .frame(width: 280)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedCarousels: some View {
        ForEach(coordinator.homeSections.dropFirst()) { section in
            if !section.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
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
                                        .frame(width: 148, height: 148)
                                        Text(track.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(track.artistDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.64))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 148)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
