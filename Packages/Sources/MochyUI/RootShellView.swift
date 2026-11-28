import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// Root 4-tab navigation shell faithful 1:1 to `realidkroo/Mochy-Music`:
/// - Floating 64pt `NavPill` with frosted chrome glass, cover `accentWash`, and horizontal pill drag
/// - MiniPlayer with horizontal swipe-to-skip & live `MiniLyricsTicker`
/// - Continuous finger-following `BottomSheetPlayer` with background scale depth (`1 - 0.06 * p`) & `StatusBarLeavesAt = 0.82`
/// - First-launch `SetupWizardView` featuring the Brushed Silver `ProfileIdCard`
public struct RootShellView: View {
    @Bindable public var coordinator: AppCoordinator
    @Namespace private var coverNamespace
    @State private var dragTranslation: CGFloat = 0
    @State private var miniSwipeOffsetX: CGFloat = 0
    @State private var showOnboarding = false
    @State private var isKeyboardVisible = false

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        GeometryReader { screenGeo in
            let bottomSafeInset = screenGeo.safeAreaInsets.bottom
            // Rest floating NavPill directly above the thin iOS Home Indicator (~13pt from physical bottom)
            // without double-counting the 34pt safe-area inset (1:1 with Mochy's tight 8dp bottom margin).
            let navBottomPadding: CGFloat = bottomSafeInset > 0 ? 14 : 8

            ZStack {
                // Background Tabs (respect keyboard safe area so SearchScreen input never gets obscured)
                Group {
                    switch coordinator.selectedTab {
                    case .home:
                        HomeScreen(coordinator: coordinator)
                    case .search:
                        SearchScreen(coordinator: coordinator)
                    case .library:
                        LibraryScreen(coordinator: coordinator)
                    case .settings:
                        MochySettingsScreen(coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.0 - 0.06 * coordinator.activeProgress)
                .opacity(max(0.0, 1.0 - coordinator.activeProgress * 0.85))
                .allowsHitTesting(coordinator.activeProgress < 0.25)

                // Floating Chrome + Morphing Player pinned to physical bottom edge (ignoring bottom & keyboard safe areas)
                GeometryReader { geo in
                    let maxHeight = max(geo.size.height, 640)
                    let progress = effectiveExpansionProgress(maxHeight: maxHeight)

                    ZStack(alignment: .bottom) {
                        VStack(spacing: 8) {
                            if let current = coordinator.player.currentItem, !coordinator.isPlayerExpanded {
                                miniPlayerBar(item: current)
                                    .offset(x: miniSwipeOffsetX)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .gesture(miniPlayerGesture(maxHeight: maxHeight))
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                                            coordinator.isPlayerExpanded = true
                                            dragTranslation = 0
                                        }
                                    }
                            }

                            floatingNavPill
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, navBottomPadding)
                        .offset(y: 160 * progress)
                        .opacity(isKeyboardVisible ? 0 : max(0.0, 1.0 - Double(progress) / 0.58))
                        .allowsHitTesting(!isKeyboardVisible && progress < 0.25)

                        if coordinator.player.currentItem != nil && (coordinator.isPlayerExpanded || dragTranslation < -8) {
                            FullPlayerContainerView(
                                coordinator: coordinator,
                                coverNamespace: coverNamespace,
                                dragProgress: progress,
                                onCollapse: {
                                    withAnimation(.spring(response: 0.40, dampingFraction: 0.88)) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(.keyboard)
            }
        }
        .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
        #if os(iOS)
        .statusBarHidden(coordinator.isPlayerExpanded && dragTranslation < 48)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = false }
        }
        #endif
        .preferredColorScheme(.dark)
        .onChange(of: coordinator.player.currentItem?.id) { _, _ in
            coordinator.onTrackChanged()
        }
        .onChange(of: coordinator.player.isPlaying) { _, _ in
            coordinator.publishLiveActivityState()
        }
        .onAppear {
            if !coordinator.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .task {
            await coordinator.loadHomeFeedIfNeeded()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            SetupWizardView(coordinator: coordinator) {
                coordinator.settings.hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            SetupWizardView(coordinator: coordinator) {
                coordinator.settings.hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
        #endif
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

    private func miniPlayerGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.height) >= abs(value.translation.width) {
                    if value.translation.height < 0 {
                        dragTranslation = value.translation.height
                    }
                    miniSwipeOffsetX = 0
                } else {
                    miniSwipeOffsetX = max(-90, min(90, value.translation.width * 0.65))
                }
            }
            .onEnded { value in
                if abs(value.translation.height) >= abs(value.translation.width) {
                    if value.translation.height < -80 || value.predictedEndTranslation.height < -180 {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            coordinator.isPlayerExpanded = true
                            dragTranslation = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                            dragTranslation = 0
                        }
                    }
                } else {
                    if value.translation.width < -55 {
                        coordinator.player.skipNext()
                    } else if value.translation.width > 55 {
                        coordinator.player.skipPrevious()
                    }
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        miniSwipeOffsetX = 0
                    }
                }
            }
    }

    private func fullPlayerDragGesture(maxHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                    dragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > maxHeight * 0.20 || value.predictedEndTranslation.height > maxHeight * 0.45 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        coordinator.isPlayerExpanded = false
                        dragTranslation = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    private func miniPlayerBar(item: PlaybackItem) -> some View {
        let pct = coordinator.player.duration > 0
            ? min(1.0, max(0.0, coordinator.player.currentTime / coordinator.player.duration))
            : 0.0
        let liveLyric = coordinator.activeLyricLineText()

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkImageView(urlString: item.thumbnailURL, cornerRadius: 10)
                    .frame(width: 44, height: 44)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    // MiniLyricsTicker: surfaces synced active lyric line on the collapsed bar just like Mochy Music.
                    if !liveLyric.isEmpty && coordinator.player.isPlaying {
                        Text(liveLyric)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                            .id(liveLyric)
                            .transition(.opacity)
                    } else {
                        Text(item.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if coordinator.player.isBuffering {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 34, height: 34)
                } else {
                    Button {
                        coordinator.player.togglePlayPause()
                    } label: {
                        Image(systemName: coordinator.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                }

                Button {
                    coordinator.player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 34)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.10))
                    Rectangle()
                        .fill(.white.opacity(0.82))
                        .frame(width: barGeo.size.width * pct)
                }
            }
            .frame(height: 1.5)
        }
        .background(Color(white: 0.09).opacity(0.90))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.42), radius: 14, y: 5)
    }

    private var floatingNavPill: some View {
        let tabs = RootNavTab.allCases

        return GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(tabs, id: \.self) { tab in
                    let isSelected = coordinator.selectedTab == tab
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                            coordinator.onSelectTab(tab)
                        }
                        #if os(iOS) && canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                    } label: {
                        Image(systemName: isSelected ? tab.systemImage : tab.inactiveSystemImage)
                            .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.54))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(.white.opacity(0.14))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 4)
                                }
                            }
                    }
                    .buttonStyle(NavBounceButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { val in
                        let idx = Int((val.location.x / max(1, geo.size.width)) * CGFloat(tabs.count))
                        let clamped = max(0, min(tabs.count - 1, idx))
                        if tabs[clamped] != coordinator.selectedTab {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                coordinator.selectedTab = tabs[clamped]
                            }
                            #if os(iOS) && canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                        }
                    }
            )
        }
        .frame(height: 60)
        .background(Color(white: 0.10).opacity(0.84))
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.48), radius: 18, y: 7)
    }
}

private struct NavBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
