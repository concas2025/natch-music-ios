import MochyAudio
import MochyCore
import SwiftUI

/// Root 4-tab navigation shell with Mochy's floating `NavPill` and morphing `BottomSheetPlayer`.
public struct RootShellView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var dragTranslation: CGFloat = 0

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        GeometryReader { geo in
            let maxHeight = max(geo.size.height, 640)
            let progress = effectiveExpansionProgress(maxHeight: maxHeight)

            ZStack(alignment: .bottom) {
                // Background Tabs inside offscreen compositing group for smooth 120Hz scale/fade
                Group {
                    switch coordinator.selectedTab {
                    case .home:
                        HomeScreen(coordinator: coordinator)
                    case .search:
                        SearchScreen(coordinator: coordinator)
                    case .library:
                        LibraryScreen(coordinator: coordinator)
                    case .settings:
                        SettingsScreen(coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.0 - 0.06 * progress)
                .opacity(max(0.0, 1.0 - progress * 0.85))
                .drawingGroup()
                .allowsHitTesting(progress < 0.25)

                // Floating NavPill + Collapsed MiniPlayer
                VStack(spacing: 10) {
                    if let current = coordinator.player.currentItem, !coordinator.isPlayerExpanded {
                        miniPlayerBar(item: current)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .gesture(miniPlayerDragGesture(maxHeight: maxHeight))
                            .onTapGesture {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    coordinator.isPlayerExpanded = true
                                    dragTranslation = 0
                                }
                            }
                    }

                    floatingNavPill
                }
                .padding(.horizontal, 14)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 10))
                .offset(y: 120 * progress)
                .opacity(max(0.0, 1.0 - Double(progress) / 0.55))

                // Morphing Fullscreen Player Sheet
                if coordinator.player.currentItem != nil && (coordinator.isPlayerExpanded || dragTranslation < -8) {
                    FullPlayerContainerView(
                        coordinator: coordinator,
                        dragProgress: progress,
                        onCollapse: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                coordinator.isPlayerExpanded = false
                                dragTranslation = 0
                            }
                        }
                    )
                    .offset(y: sheetYOffset(maxHeight: maxHeight))
                    .gesture(fullPlayerDragGesture(maxHeight: maxHeight))
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
                }
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
        }
        #if os(iOS)
        .statusBarHidden(coordinator.isPlayerExpanded && dragTranslation < 40)
        #endif
        .preferredColorScheme(.dark)
        .onChange(of: coordinator.player.currentItem?.id) { _, _ in
            coordinator.onTrackChanged()
        }
        .task {
            await coordinator.loadHomeFeedIfNeeded()
        }
    }

    private func effectiveExpansionProgress(maxHeight: CGFloat) -> CGFloat {
        if coordinator.isPlayerExpanded {
            let collapse = max(0, dragTranslation) / maxHeight
            return max(0, min(1, 1 - collapse))
        } else {
            let expand = max(0, -dragTranslation) / maxHeight
            return max(0, min(1, expand))
        }
    }

    private func sheetYOffset(maxHeight: CGFloat) -> CGFloat {
        if coordinator.isPlayerExpanded {
            return max(0, dragTranslation)
        } else {
            return max(0, maxHeight + dragTranslation)
        }
    }

    private func miniPlayerDragGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if value.translation.height < 0 {
                    dragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height < -90 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        coordinator.isPlayerExpanded = true
                        dragTranslation = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    private func fullPlayerDragGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > maxHeight * 0.22 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        coordinator.isPlayerExpanded = false
                        dragTranslation = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    private func miniPlayerBar(item: PlaybackItem) -> some View {
        let pct = coordinator.player.duration > 0
            ? min(1.0, max(0.0, coordinator.player.currentTime / coordinator.player.duration))
            : 0.0

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkImageView(urlString: item.thumbnailURL, cornerRadius: 10)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    coordinator.player.togglePlayPause()
                } label: {
                    Image(systemName: coordinator.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }

                Button {
                    coordinator.player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            GeometryReader { barGeo in
                Rectangle()
                    .fill(coordinator.paletteColors.first ?? MochyTheme.defaultAccent)
                    .frame(width: barGeo.size.width * pct, height: 2.5)
            }
            .frame(height: 2.5)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
        )
    }

    private var floatingNavPill: some View {
        HStack(spacing: 6) {
            ForEach(RootNavTab.allCases, id: \.self) { tab in
                let isSelected = coordinator.selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        coordinator.onSelectTab(tab)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white.opacity(0.14))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }
}
