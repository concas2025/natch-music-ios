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
    @State private var showLyricsSheet = false
    @State private var showShareStudio = false
    @State private var showQueueSheet = false
    @State private var showStreamInfo = false
    @State private var showSleepTimer = false
    @State private var showPlayerStudio = false

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

            topChromeBar
                .padding(.horizontal, 18)
                .padding(.top, 52)
        }
        .background(.black)
        .ignoresSafeArea()
        .sheet(isPresented: $showStylePicker) {
            PlayerSelectorSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAudioLab) {
            AudioLabView(coordinator: coordinator)
        }
        .sheet(isPresented: $showLyricsSheet) {
            LyricsStageView(coordinator: coordinator)
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
    }

    @ViewBuilder
    private var playerStyleContent: some View {
        switch coordinator.settings.playerStyle {
        case .flagship:
            FlagshipPlayerView(
                coordinator: coordinator,
                coverNamespace: coverNamespace,
                showPlayerStudio: $showPlayerStudio,
                onOpenLyrics: { showLyricsSheet = true },
                onOpenQueue: { showQueueSheet = true },
                onOpenAudioLab: { showAudioLab = true },
                onOpenShare: { showShareStudio = true },
                onOpenStreamInfo: { showStreamInfo = true }
            )
        case .turntable:
            TurntablePlayerView(
                coordinator: coordinator,
                onOpenLyrics: { showLyricsSheet = true },
                onOpenQueue: { showQueueSheet = true },
                onOpenAudioLab: { showAudioLab = true }
            )
        case .video:
            VideoPlayerView(
                coordinator: coordinator,
                onOpenLyrics: { showLyricsSheet = true },
                onOpenQueue: { showQueueSheet = true }
            )
        case .ipod:
            IpodPlayerView(coordinator: coordinator)
        case .poster:
            PosterPlayerView(
                coordinator: coordinator,
                onOpenLyrics: { showLyricsSheet = true }
            )
        case .timeline:
            TimelinePlayerView(coordinator: coordinator)
        case .lyrics:
            LyricsStylePlayerView(
                coordinator: coordinator,
                onOpenFullLyrics: { showLyricsSheet = true }
            )
        case .bedside:
            BedsidePlayerView(coordinator: coordinator)
        case .bedsideTiles:
            BedsideTilesPlayerView(coordinator: coordinator)
        case .module:
            ModuleSkinPlayerView(
                coordinator: coordinator,
                onOpenQueue: { showQueueSheet = true },
                onOpenLyrics: { showLyricsSheet = true }
            )
        }
    }

    private var topChromeBar: some View {
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
                showStreamInfo = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(coordinator.settings.audioPassEnabled ? Color.green : Color.white.opacity(0.72))
                        .frame(width: 6, height: 6)
                    Text(coordinator.player.activeQualityBadge.isEmpty ? coordinator.settings.playerStyle.displayName : coordinator.player.activeQualityBadge)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.36))
                .clipShape(Capsule())
            }

            Spacer()

            if coordinator.settings.playerStyle == .flagship {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        showPlayerStudio.toggle()
                    }
                } label: {
                    Image(systemName: showPlayerStudio ? "checkmark.circle.fill" : "wand.and.stars")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(showPlayerStudio ? MochyTheme.defaultAccent : .white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.32))
                        .clipShape(Circle())
                }
            }

            Menu {
                Button {
                    showStylePicker = true
                } label: {
                    Label("Player Style (\(coordinator.settings.playerStyle.displayName))", systemImage: "sparkles.rectangle.stack")
                }
                Button {
                    showAudioLab = true
                } label: {
                    Label("Audio Lab & 3D Stage", systemImage: "slider.vertical.3")
                }
                Button {
                    showQueueSheet = true
                } label: {
                    Label("Up Next Queue (\(coordinator.player.queue.count))", systemImage: "list.bullet")
                }
                Button {
                    showLyricsSheet = true
                } label: {
                    Label("Lyrics Stage", systemImage: "quote.bubble")
                }
                Button {
                    showShareStudio = true
                } label: {
                    Label("Share Card & Video Studio", systemImage: "square.and.arrow.up")
                }
                Button {
                    showSleepTimer = true
                } label: {
                    let suffix = coordinator.player.sleepTimerRemainingSeconds.map { " (\($0 / 60)m)" } ?? ""
                    Label("Sleep Timer\(suffix)", systemImage: "moon.zzz")
                }
                Divider()
                Button {
                    coordinator.pinCurrentToSpeedDial()
                } label: {
                    Label("Pin to Speed Dial", systemImage: "pin")
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
