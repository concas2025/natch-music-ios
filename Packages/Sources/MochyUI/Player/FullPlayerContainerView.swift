import MochyAudio
import MochyCore
import SwiftUI

public struct FullPlayerContainerView: View {
    @Bindable public var coordinator: AppCoordinator
    public var coverNamespace: Namespace.ID
    public var dragProgress: CGFloat
    public let onCollapse: () -> Void

    @State private var showStylePicker = false
    @State private var showAudioLab = false
    @State private var showLyricsOverlay = false
    @State private var showLyricsOffsetControls = false
    @State private var showShareStudio = false
    @State private var showQueueSheet = false
    @State private var showStreamInfo = false
    @State private var showSleepTimer = false
    @State private var showPlayerStudio = false
    @State private var showActionMenu = false
    @State private var showAddToPlaylist = false

    public init(
        coordinator: AppCoordinator,
        coverNamespace: Namespace.ID,
        dragProgress: CGFloat = 1,
        onCollapse: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.coverNamespace = coverNamespace
        self.dragProgress = dragProgress
        self.onCollapse = onCollapse
    }

    public var body: some View {
        ZStack(alignment: .top) {
            playerStyleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if coordinator.settings.playerStyle != .flagship {
                nonFlagshipTopChrome
                    .padding(.horizontal, 18)
                    .padding(.top, 52)
            }

            if showLyricsOverlay {
                LyricsStageView(
                    coordinator: coordinator,
                    showControls: $showLyricsOffsetControls,
                    onDismiss: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            showLyricsOverlay = false
                            showLyricsOffsetControls = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }

            if showActionMenu {
                PlayerActionMenuOverlay(
                    coordinator: coordinator,
                    isPresented: $showActionMenu,
                    onOpenAudioLab: { showAudioLab = true },
                    onOpenStylePicker: { showStylePicker = true },
                    onOpenAddToPlaylist: { showAddToPlaylist = true },
                    onOpenStreamInfo: { showStreamInfo = true },
                    onOpenSleepTimer: { showSleepTimer = true },
                    onOpenLyricsWithOffset: {
                        showLyricsOffsetControls = true
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            showLyricsOverlay = true
                        }
                    },
                    onOpenShare: { showShareStudio = true }
                )
                .zIndex(30)
            }

            if let toast = coordinator.menuToastMessage, !toast.isEmpty {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.7))
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(40)
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: showLyricsOverlay)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: showActionMenu)
        .sheet(isPresented: $showStylePicker) {
            PlayerSelectorSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAudioLab) {
            AudioLabView(coordinator: coordinator)
        }
        .sheet(isPresented: $showShareStudio) {
            SongShareStudioView(coordinator: coordinator)
        }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheetView(coordinator: coordinator)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStreamInfo) {
            StreamInfoSheet(coordinator: coordinator)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet(coordinator: coordinator)
                .presentationDetents([.fraction(0.4)])
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistPickerSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var playerStyleContent: some View {
        let openLyrics: () -> Void = {
            showLyricsOffsetControls = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                showLyricsOverlay = true
            }
        }
        switch coordinator.settings.playerStyle {
        case .flagship:
            FlagshipPlayerView(
                coordinator: coordinator,
                coverNamespace: coverNamespace,
                showPlayerStudio: $showPlayerStudio,
                onCollapse: onCollapse,
                onOpenLyrics: openLyrics,
                onOpenQueue: { showQueueSheet = true },
                onOpenActionMenu: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        showActionMenu = true
                    }
                },
                onOpenStreamInfo: { showStreamInfo = true }
            )
        case .turntable:
            TurntablePlayerView(
                coordinator: coordinator,
                onOpenLyrics: openLyrics,
                onOpenQueue: { showQueueSheet = true },
                onOpenAudioLab: { showAudioLab = true }
            )
        case .video:
            VideoPlayerView(
                coordinator: coordinator,
                onOpenLyrics: openLyrics,
                onOpenQueue: { showQueueSheet = true }
            )
        case .ipod:
            IpodPlayerView(coordinator: coordinator)
        case .poster:
            PosterPlayerView(
                coordinator: coordinator,
                onOpenLyrics: openLyrics
            )
        case .timeline:
            TimelinePlayerView(coordinator: coordinator)
        case .lyrics:
            LyricsStylePlayerView(
                coordinator: coordinator,
                onOpenFullLyrics: openLyrics
            )
        case .bedside:
            BedsidePlayerView(coordinator: coordinator)
        case .bedsideTiles:
            BedsideTilesPlayerView(coordinator: coordinator)
        case .module:
            ModuleSkinPlayerView(
                coordinator: coordinator,
                onOpenQueue: { showQueueSheet = true },
                onOpenLyrics: openLyrics
            )
        }
    }

    private var nonFlagshipTopChrome: some View {
        HStack(spacing: 10) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.32))
                    .clipShape(Circle())
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    showActionMenu = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.32))
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - 10 Player Styles Visual Picker

public struct PlayerSelectorSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PlayerStyle.allCases, id: \.self) { style in
                        let selected = coordinator.settings.playerStyle == style
                        Button {
                            coordinator.settings.playerStyle = style
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: icon(for: style))
                                        .font(.title3)
                                        .foregroundStyle(selected ? MochyTheme.defaultAccent : .white)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(MochyTheme.defaultAccent)
                                    }
                                }
                                Text(style.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(subtitle(for: style))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Color.white.opacity(0.14) : MochyTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(selected ? Color.white.opacity(0.55) : MochyTheme.subtleBorder, lineWidth: selected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("10 Player Styles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private func icon(for style: PlayerStyle) -> String {
        switch style {
        case .flagship: return "music.note.house.fill"
        case .turntable: return "opticaldisc.fill"
        case .video: return "play.tv.fill"
        case .ipod: return "ipod"
        case .poster: return "circle.lefthalf.filled"
        case .timeline: return "clock.arrow.2.circlepath"
        case .lyrics: return "text.quote"
        case .bedside: return "bed.double.fill"
        case .bedsideTiles: return "rectangle.split.2x1.fill"
        case .module: return "puzzlepiece.extension.fill"
        }
    }

    private func subtitle(for style: PlayerStyle) -> String {
        switch style {
        case .flagship: return "Ambient backdrop, clean bar & WYSIWYG Studio"
        case .turntable: return "Spinning vinyl grooves & draggable S-tonearm"
        case .video: return "Synchronized music video up to 4K"
        case .ipod: return "4 iconic chassis, Click Wheel & Cover Flow 3D"
        case .poster: return "Off-center rim cover, FFT ring & bold lyrics"
        case .timeline: return "Two-tone playhead split & giant riding clock"
        case .lyrics: return "Expressive chorus overlay on riding timeline"
        case .bedside: return "4 nightstand clocks, OLED shift & amber tint"
        case .bedsideTiles: return "Adaptive dual-tile desk & nightstand view"
        case .module: return "Manifest-driven block layout skin"
        }
    }
}

// MARK: - Stream Info & Provider Switcher Sheet

public struct StreamInfoSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let providers: [(id: String, name: String, desc: String)] = [
        ("monochrome", "Monochrome FLAC", "Lossless 16/24-bit FLAC streams"),
        ("jiosaavn", "JioSaavn 320k", "High-bitrate AAC 320 kbps"),
        ("youtube", "YouTube InnerTube", "Native fMP4/AAC via LocalAudioProxy"),
        ("applemusic", "Apple Music (MusicKit)", "FairPlay DRM catalog match"),
    ]

    public var body: some View {
        NavigationStack {
            List {
                Section("Active Stream Telemetry") {
                    LabeledContent("Source", value: coordinator.player.activeSourceLabel.isEmpty ? "Idle" : coordinator.player.activeSourceLabel)
                    LabeledContent("Format", value: coordinator.player.activeQualityBadge.isEmpty ? "—" : coordinator.player.activeQualityBadge)
                    LabeledContent("DSP Engine", value: coordinator.settings.audioPassEnabled ? "Audio Pass (Bit-Exact Bypass)" : "C++ MTAudioProcessingTap Active")
                    if coordinator.player.isCrossmixing {
                        LabeledContent("Crossmix DJ", value: coordinator.player.activeCrossmixStyle.rawValue)
                    }
                    if let err = coordinator.player.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Switch Source for Current Track") {
                    ForEach(providers, id: \.id) { p in
                        Button {
                            coordinator.player.forceSwitchProvider(to: p.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).foregroundStyle(.white)
                                    Text(p.desc).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if coordinator.player.activeSourceId == p.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(MochyTheme.defaultAccent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stream Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sleep Timer Sheet

public struct SleepTimerSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let presets = [10, 15, 30, 45, 60, 90]

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let rem = coordinator.player.sleepTimerRemainingSeconds {
                    Text("Pausing in \(MochyTimeFormatter.format(TimeInterval(rem)))")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(MochyTheme.defaultAccent)
                    Button("Cancel Sleep Timer", role: .destructive) {
                        coordinator.player.cancelSleepTimer()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(presets, id: \.self) { mins in
                        Button("\(mins) min") {
                            coordinator.player.setSleepTimer(minutes: mins)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(MochyTheme.cardSurface)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 16)
            .background(.black)
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .preferredColorScheme(.dark)
    }
}
