import AVFoundation
import AVKit
import MochyAudio
import MochyCore
import MochyModules
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Full Player Container Switching All 10 PlayerStyles

public struct FullPlayerContainerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let dragProgress: CGFloat
    public let onCollapse: () -> Void

    @State private var showStreamInfo = false
    @State private var showLyricsOverlay = false
    @State private var showAudioLab = false
    @State private var showPlayerStudio = false

    public var body: some View {
        ZStack {
            AmbientBackdropView(
                colors: coordinator.paletteColors,
                style: coordinator.settings.flagshipBackground,
                blurQuality: coordinator.settings.blurQuality,
                isPaused: dragProgress < 0.1
            )

            VStack(spacing: 0) {
                topBar

                if showLyricsOverlay {
                    LyricsStageView(coordinator: coordinator)
                } else {
                    activePlayerStyleView
                }
            }
            .padding(.top, 50)
            .padding(.bottom, 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: max(0, (1 - dragProgress) * 32), style: .continuous))
        .sheet(isPresented: $showStreamInfo) {
            StreamInfoSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $showAudioLab) {
            NavigationStack { AudioLabView(coordinator: coordinator) }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
            }

            Spacer()

            Menu {
                Picker("Player Style", selection: $coordinator.settings.playerStyle) {
                    ForEach(PlayerStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(coordinator.settings.playerStyle.displayName)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
            }

            Spacer()

            Menu {
                Button("Lyrics Overlay", systemImage: "quote.bubble") {
                    showLyricsOverlay.toggle()
                }
                Button("Stream & Provider Switch", systemImage: "antenna.radiowaves.left.and.right") {
                    showStreamInfo = true
                }
                Button("Audio Lab & 3D Stage", systemImage: "slider.horizontal.3") {
                    showAudioLab = true
                }
                Button("Pin to Speed Dial", systemImage: "pin") {
                    coordinator.pinCurrentToSpeedDial()
                }
                Button("Player Studio (Layout)", systemImage: "wand.and.stars") {
                    showPlayerStudio.toggle()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var activePlayerStyleView: some View {
        switch coordinator.settings.playerStyle {
        case .flagship:
            FlagshipPlayerView(coordinator: coordinator, showStudio: $showPlayerStudio)
        case .turntable:
            TurntablePlayerView(coordinator: coordinator)
        case .video:
            VideoPlayerView(coordinator: coordinator)
        case .ipod:
            IpodPlayerView(coordinator: coordinator)
        case .poster:
            PosterPlayerView(coordinator: coordinator)
        case .timeline:
            TimelinePlayerView(coordinator: coordinator)
        case .lyrics:
            LyricsStageView(coordinator: coordinator)
        case .bedside:
            BedsidePlayerView(coordinator: coordinator)
        case .bedsideTiles:
            BedsideTilesPlayerView(coordinator: coordinator)
        case .module:
            ModuleSkinPlayerView(coordinator: coordinator)
        }
    }
}

// MARK: - 1. FLAGSHIP (Edge Cover, Wavy/Slim Seekbar, 3 Transport Layouts & Player Studio)

public struct FlagshipPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @Binding public var showStudio: Bool

    public var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)

            ArtworkImageView(
                urlString: coordinator.player.currentItem?.thumbnailURL,
                cornerRadius: coordinator.settings.thumbnailCornerRadius
            )
            .frame(maxWidth: 310 + coordinator.settings.playerCardGrowth, maxHeight: 310 + coordinator.settings.playerCardGrowth)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            .onLongPressGesture { showStudio.toggle() }

            if showStudio {
                HStack {
                    Text("Player Studio")
                        .font(.caption.bold())
                    Slider(value: $coordinator.settings.playerControlsShift, in: -40...40)
                    Button("Done") { showStudio = false }.font(.caption.bold())
                }
                .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coordinator.player.currentItem?.title ?? "Not Playing")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(coordinator.player.currentItem?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        if let id = coordinator.player.currentItem?.id {
                            coordinator.toggleLike(songId: id)
                        }
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(MochyTheme.defaultAccent)
                    }
                }
            }
            .padding(.horizontal, 26)
            .offset(y: coordinator.settings.playerControlsShift)

            SeekbarControlView(
                player: coordinator.player,
                style: coordinator.settings.seekbarStyle,
                accent: coordinator.paletteColors.first ?? MochyTheme.defaultAccent
            )
            .padding(.horizontal, 24)

            TransportControlsRow(coordinator: coordinator)
                .padding(.horizontal, 20)

            HStack {
                Text(coordinator.player.activeQualityBadge.isEmpty ? "Resolving..." : coordinator.player.activeQualityBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
                Spacer()
                #if os(iOS)
                AirPlayRouteButton().frame(width: 28, height: 28)
                #endif
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 4)
        }
    }
}

// MARK: - 2. TURNTABLE (Spinning Vinyl Disc + Interactive Draggable Tonearm Scrubbing)

public struct TurntablePlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var tonearmOffsetAngle: Double = 0

    public var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack(alignment: .topTrailing) {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !coordinator.player.isPlaying)) { tl in
                    let angle = coordinator.player.isPlaying
                        ? (tl.date.timeIntervalSinceReferenceDate * 45).truncatingRemainder(dividingBy: 360)
                        : 0
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(white: 0.16), .black, Color(white: 0.12), .black],
                                    center: .center,
                                    startRadius: 30,
                                    endRadius: 150
                                )
                            )
                            .frame(width: 280, height: 280)
                        ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 70)
                            .frame(width: 120, height: 120)
                        Circle().fill(.black).frame(width: 14, height: 14)
                    }
                    .rotationEffect(.degrees(angle))
                }

                // Tonearm: drag horizontally/angle to scrub track
                let progress = coordinator.player.duration > 0
                    ? coordinator.player.currentTime / coordinator.player.duration
                    : 0
                let baseAngle = 14 + progress * 24 + tonearmOffsetAngle
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.85))
                    .frame(width: 8, height: 165)
                    .rotationEffect(.degrees(baseAngle), anchor: .top)
                    .offset(x: -18, y: 12)
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                tonearmOffsetAngle = Double(val.translation.width) * 0.12
                            }
                            .onEnded { val in
                                let deltaPct = -Double(val.translation.width) / 180.0
                                let target = coordinator.player.currentTime + deltaPct * max(30, coordinator.player.duration)
                                coordinator.player.seek(to: target)
                                tonearmOffsetAngle = 0
                            }
                    )
            }

            Text(coordinator.player.currentItem?.title ?? "")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(coordinator.player.currentItem?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            TransportControlsRow(coordinator: coordinator)
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - 3. VIDEO (YouTube Music Video Stream + Floating Lyrics Toggle)

public struct VideoPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var avVideoPlayer: AVPlayer?
    @State private var showLyrics = false

    public var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if let avVideoPlayer {
                    VideoPlayer(player: avVideoPlayer)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 16)
                        .frame(height: 260)
                        .overlay {
                            ProgressView("Loading MV stream...")
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }

                Button(showLyrics ? "Hide Lyrics" : "Lyrics") {
                    showLyrics.toggle()
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .padding(.horizontal)

            if showLyrics {
                LyricsStageView(coordinator: coordinator)
            } else {
                Text(coordinator.player.currentItem?.title ?? "")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                SeekbarControlView(player: coordinator.player, style: .slim, accent: .white)
                    .padding(.horizontal, 24)
                TransportControlsRow(coordinator: coordinator)
                Spacer()
            }
        }
        .task(id: coordinator.player.currentItem?.id) {
            await coordinator.loadVideoStreamsForCurrent()
            if let best = coordinator.videoStreamOptions.first {
                let p = AVPlayer(url: best.url)
                p.isMuted = true // Keep audio routed cleanly through MochyAudioPlayer / DSP
                await p.seek(to: CMTime(seconds: coordinator.player.currentTime, preferredTimescale: 600))
                p.play()
                avVideoPlayer = p
            }
        }
    }
}

// MARK: - 4. IPOD CLASSIC (4 Chassis Themes, ClickWheel Rotary Gesture + Taptic + Cover Flow)

public struct IpodPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var screenPage = 0 // 0: Now Playing, 1: Cover Flow
    @State private var lastWheelAngle: Double?

    public var body: some View {
        VStack(spacing: 18) {
            Picker("Chassis", selection: $coordinator.settings.ipodTheme) {
                ForEach(IpodTheme.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 28)

            // iPod Screen
            VStack(spacing: 8) {
                if screenPage == 0 {
                    HStack(spacing: 12) {
                        ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 8)
                            .frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Now Playing")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.6))
                            Text(coordinator.player.currentItem?.title ?? "No Track")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(coordinator.player.currentItem?.artist ?? "")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    // 3D Cover Flow
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(coordinator.player.queue) { item in
                                ArtworkImageView(urlString: item.thumbnailURL, cornerRadius: 8)
                                    .frame(width: 96, height: 96)
                            }
                        }
                        .padding()
                    }
                }
                SeekbarControlView(player: coordinator.player, style: .slim, accent: .cyan)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            .frame(height: coordinator.settings.ipodTallScreen ? 220 : 170)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 4))
            .padding(.horizontal, 28)

            // Classic Rotary Click Wheel
            ZStack {
                Circle()
                    .fill(wheelBackground)
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.35), radius: 8)

                VStack {
                    Button("MENU") { screenPage = screenPage == 0 ? 1 : 0 }
                        .font(.caption.bold())
                        .padding(.top, 14)
                    Spacer()
                    Button { coordinator.player.togglePlayPause() } label: {
                        Image(systemName: "playpause.fill").font(.subheadline)
                    }
                    .padding(.bottom, 14)
                }
                .frame(height: 220)

                HStack {
                    Button { coordinator.player.skipPrevious() } label: {
                        Image(systemName: "backward.end.fill").padding(.leading, 14)
                    }
                    Spacer()
                    Button { coordinator.player.skipNext() } label: {
                        Image(systemName: "forward.end.fill").padding(.trailing, 14)
                    }
                }
                .frame(width: 220)

                Circle()
                    .fill(chassisCenterColor)
                    .frame(width: 76, height: 76)
                    .onTapGesture { coordinator.player.togglePlayPause() }
            }
            .foregroundStyle(coordinator.settings.ipodTheme == .silver ? .black : .white)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let cx = 110.0, cy = 110.0
                        let angle = atan2(val.location.y - cy, val.location.x - cx)
                        if let prev = lastWheelAngle {
                            var delta = angle - prev
                            if delta > .pi { delta -= 2 * .pi }
                            if delta < -.pi { delta += 2 * .pi }
                            if abs(delta) > 0.18 {
                                coordinator.player.seek(to: coordinator.player.currentTime + (delta > 0 ? 3.0 : -3.0))
                                lastWheelAngle = angle
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }
                        } else {
                            lastWheelAngle = angle
                        }
                    }
                    .onEnded { _ in lastWheelAngle = nil }
            )

            Spacer()
        }
        .padding(.vertical)
        .background(chassisBackground.opacity(0.45), in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 14)
    }

    private var chassisBackground: Color {
        switch coordinator.settings.ipodTheme {
        case .silver: return Color(white: 0.78)
        case .black: return Color(white: 0.16)
        case .u2: return Color(red: 0.12, green: 0.06, blue: 0.08)
        case .trueDark: return .black
        }
    }

    private var wheelBackground: Color {
        switch coordinator.settings.ipodTheme {
        case .silver: return .white
        case .u2: return MochyTheme.defaultAccent
        case .black, .trueDark: return Color(white: 0.22)
        }
    }

    private var chassisCenterColor: Color {
        coordinator.settings.ipodTheme == .silver ? Color(white: 0.85) : Color(white: 0.10)
    }
}

// MARK: - 5–10 Remaining Player Styles (Poster, Timeline, Bedside, BedsideTiles, Module)

public struct PosterPlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                ForEach(Array(coordinator.player.spectrumBins.enumerated()), id: \.offset) { idx, mag in
                    let angle = Angle.degrees(Double(idx) / 32.0 * 360.0)
                    Capsule()
                        .fill(.white.opacity(0.65))
                        .frame(width: 4, height: 10 + CGFloat(mag) * 34)
                        .offset(y: -145)
                        .rotationEffect(angle)
                }
                ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 120)
                    .frame(width: 230, height: 230)
            }
            Text(coordinator.player.currentItem?.title ?? "")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(coordinator.player.currentItem?.artist ?? "")
                .foregroundStyle(.white.opacity(0.72))
            SeekbarControlView(player: coordinator.player, style: .wavy, accent: .white)
                .padding(.horizontal, 24)
            TransportControlsRow(coordinator: coordinator)
            Spacer()
        }
    }
}

public struct TimelinePlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text(coordinator.player.currentItem?.artist.uppercased() ?? "")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.65))
            Text(coordinator.player.currentItem?.title ?? "")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(.white)
            SeekbarControlView(player: coordinator.player, style: .wavy, accent: coordinator.paletteColors.first ?? .white)
            TransportControlsRow(coordinator: coordinator)
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

public struct BedsidePlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var driftOffset: CGSize = .zero

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let tint = coordinator.settings.bedsideNightTint ? Color.orange : Color.white
            VStack(spacing: 16) {
                Spacer()
                Text(timeline.date, style: .time)
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .foregroundStyle(tint)
                Text(coordinator.player.currentItem?.title ?? "")
                    .font(.headline)
                    .foregroundStyle(tint.opacity(0.8))
                TransportControlsRow(coordinator: coordinator)
                Spacer()
            }
            .offset(driftOffset)
            .onChange(of: timeline.date) { _, _ in
                driftOffset = CGSize(width: CGFloat.random(in: -5...5), height: CGFloat.random(in: -5...5))
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }
}

public struct BedsideTilesPlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        HStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 30)) { tl in
                VStack(alignment: .leading, spacing: 8) {
                    Text(tl.date, style: .time)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(coordinator.settings.bedsideNightTint ? .orange : .white)
                    Text(coordinator.player.currentItem?.title ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20))
            }

            VStack(spacing: 14) {
                ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 16)
                    .frame(width: 120, height: 120)
                TransportControlsRow(coordinator: coordinator)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20))
        }
        .padding()
    }
}

public struct ModuleSkinPlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        let skin = coordinator.currentModuleSkin
        let accent = MochyTheme.colorFromHex(skin.accentHex) ?? MochyTheme.defaultAccent
        VStack(spacing: 16) {
            ForEach(skin.blocks) { block in
                renderBlock(block, accent: accent)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func renderBlock(_ block: ModuleSkinManifest.Block, accent: Color) -> some View {
        switch block.kind {
        case "cover":
            ArtworkImageView(
                urlString: coordinator.player.currentItem?.thumbnailURL,
                cornerRadius: block.cornerRadius ?? 18
            )
            .frame(height: block.height ?? 260)
            .aspectRatio(1, contentMode: .fit)
        case "title":
            Text(coordinator.player.currentItem?.title ?? "")
                .font(.title2.bold())
                .foregroundStyle(.white)
        case "visualizer":
            skinVisualizer(height: block.height ?? 48, accent: accent)
        case "seekbar":
            SeekbarControlView(player: coordinator.player, style: .wavy, accent: accent)
        case "transport":
            TransportControlsRow(coordinator: coordinator)
        default:
            EmptyView()
        }
    }

    private func skinVisualizer(height: Double, accent: Color) -> some View {
        let bins = coordinator.player.spectrumBins
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bins.count, id: \.self) { idx in
                let barHeight = max(CGFloat(4), CGFloat(bins[idx]) * CGFloat(44))
                Capsule()
                    .fill(accent)
                    .frame(height: barHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Shared Controls (Seekbar, Transport, StreamInfoSheet + ProviderSwitch)

public struct SeekbarControlView: View {
    public let player: MochyAudioPlayer
    public let style: SeekbarStyle
    public let accent: Color

    public var body: some View {
        let total = max(1, player.duration)
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { min(player.currentTime, total) },
                    set: { player.seek(to: $0) }
                ),
                in: 0...total
            )
            .tint(accent)

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func formatTime(_ secs: TimeInterval) -> String {
        guard secs.isFinite && secs >= 0 else { return "0:00" }
        let s = Int(secs)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

public struct TransportControlsRow: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        HStack(spacing: 26) {
            if coordinator.settings.transportLayout == .tenSeconds {
                Button {
                    coordinator.player.seek(to: coordinator.player.currentTime - 10)
                } label: {
                    Image(systemName: "gobackward.10").font(.title2)
                }
            } else if coordinator.settings.transportLayout == .queueRepeat {
                Button {
                    coordinator.player.shuffleEnabled.toggle()
                } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(coordinator.player.shuffleEnabled ? MochyTheme.defaultAccent : .white.opacity(0.75))
                }
            }

            Button { coordinator.player.skipPrevious() } label: {
                Image(systemName: "backward.fill").font(.title)
            }

            Button { coordinator.player.togglePlayPause() } label: {
                Image(systemName: coordinator.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 62))
            }

            Button { coordinator.player.skipNext() } label: {
                Image(systemName: "forward.fill").font(.title)
            }

            if coordinator.settings.transportLayout == .tenSeconds {
                Button {
                    coordinator.player.seek(to: coordinator.player.currentTime + 10)
                } label: {
                    Image(systemName: "goforward.10").font(.title2)
                }
            } else if coordinator.settings.transportLayout == .queueRepeat {
                Button {
                    switch coordinator.player.repeatMode {
                    case .off: coordinator.player.repeatMode = .all
                    case .all: coordinator.player.repeatMode = .one
                    case .one: coordinator.player.repeatMode = .off
                    }
                } label: {
                    Image(systemName: coordinator.player.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(coordinator.player.repeatMode == .off ? .white.opacity(0.75) : MochyTheme.defaultAccent)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

public struct StreamInfoSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section("Active Playback Route") {
                    LabeledContent("Source", value: coordinator.player.activeSourceLabel)
                    LabeledContent("Quality", value: coordinator.player.activeQualityBadge)
                    if coordinator.player.isDRMStream {
                        Text("FairPlay DRM active — iOS disables custom Audio Engine DSP for Apple Music streams.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Provider Switch (Force Source)") {
                    ForEach(["monochrome", "jiosaavn", "youtube", "applemusic"], id: \.self) { src in
                        Button("Force Switch to \(src.capitalized)") {
                            coordinator.player.forceSwitchProvider(to: src)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Stream Info")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

#if os(iOS)
private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(MochyTheme.defaultAccent)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
