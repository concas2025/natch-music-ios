import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// 1:1 Mochy Music Flagship Player (Full Artwork Default + Long-Press WYSIWYG Studio).
public struct FlagshipPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public var coverNamespace: Namespace.ID
    @Binding public var showPlayerStudio: Bool
    public let onCollapse: () -> Void
    public let onOpenLyrics: () -> Void
    public let onOpenQueue: () -> Void
    public let onOpenActionMenu: () -> Void
    public let onOpenStreamInfo: () -> Void

    public init(
        coordinator: AppCoordinator,
        coverNamespace: Namespace.ID,
        showPlayerStudio: Binding<Bool>,
        onCollapse: @escaping () -> Void = {},
        onOpenLyrics: @escaping () -> Void,
        onOpenQueue: @escaping () -> Void,
        onOpenActionMenu: @escaping () -> Void,
        onOpenStreamInfo: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.coverNamespace = coverNamespace
        self._showPlayerStudio = showPlayerStudio
        self.onCollapse = onCollapse
        self.onOpenLyrics = onOpenLyrics
        self.onOpenQueue = onOpenQueue
        self.onOpenActionMenu = onOpenActionMenu
        self.onOpenStreamInfo = onOpenStreamInfo
    }

    public var body: some View {
        let item = coordinator.player.currentItem
        let coverTint = coordinator.paletteColors.first ?? Color(white: 0.16)
        let accentTint = coordinator.paletteColors.indices.contains(1) ? coordinator.paletteColors[1] : .white.opacity(0.92)
        let isFull = coordinator.settings.playerCoverStyle == .full

        GeometryReader { geo in
            ZStack {
                AmbientBackdropView(
                    colors: coordinator.paletteColors,
                    style: coordinator.settings.flagshipBackground,
                    blurQuality: coordinator.settings.blurQuality,
                    isPaused: !coordinator.player.isPlaying
                )
                .onLongPressGesture(minimumDuration: 0.45) {
                    togglePlayerStudio()
                }

                if isFull {
                    fullBleedArtworkLayer(item: item, size: geo.size, coverTint: coverTint)
                }

                VStack(spacing: 0) {
                    // Subtle Mochy top chrome: drag handle + "Playing from <source>"
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: 40, height: 4)
                        Text("Playing from \(coordinator.playingFromLabel)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                    }
                    .padding(.top, max(geo.safeAreaInsets.top + 8, 56))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onCollapse)

                    if isFull {
                        Spacer(minLength: geo.size.height * 0.28)
                    } else {
                        Spacer(minLength: 14)
                        coverSection(item: item, viewport: geo.size)
                            .onLongPressGesture(minimumDuration: 0.45) {
                                togglePlayerStudio()
                            }
                        Spacer(minLength: 14)
                    }

                    // Track Metadata Row + Favorite Star + (...) Menu Button
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            MochyMarqueeText(
                                item?.title ?? "Not Playing",
                                font: .system(size: 21, weight: .bold),
                                color: .white
                            )
                            MochyMarqueeText(
                                item?.artist ?? "Select a track",
                                font: .system(size: 16, weight: .medium),
                                color: .white.opacity(0.74)
                            )
                        }

                        Spacer(minLength: 8)

                        HStack(spacing: 10) {
                            if let id = item?.id {
                                let isFav = coordinator.isLiked(songId: id)
                                Button {
                                    coordinator.toggleLike(songId: id)
                                    #if os(iOS) && canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    #endif
                                } label: {
                                    Image(systemName: isFav ? "star.fill" : "star")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(isFav ? Color.yellow : .white)
                                        .frame(width: 34, height: 34)
                                        .background(.white.opacity(0.16))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: onOpenActionMenu) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.16))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, CGFloat(coordinator.settings.playerControlsShift) * 0.25)

                    // Live lyric preview above seekbar (tap to open in-app Lyrics overlay)
                    Button(action: onOpenLyrics) {
                        Text(coordinator.activeLyricLineText())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                    MochySeekbarView(coordinator: coordinator, accentColor: accentTint)
                        .padding(.horizontal, 24)

                    if let err = coordinator.player.lastError, !err.isEmpty {
                        HStack(spacing: 8) {
                            Button(action: onOpenStreamInfo) {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button("Retry") {
                                coordinator.player.retryCurrentTrack()
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }

                    TransportControlsRow(coordinator: coordinator, onOpenQueue: onOpenQueue, flagshipMinimal: true)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    MochyVolumeBar()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)

                    flagshipBottomBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 22))
                }
                .offset(y: CGFloat(coordinator.settings.playerControlsShift))

                if showPlayerStudio {
                    playerStudioOverlay
                }
            }
        }
    }

    private func togglePlayerStudio() {
        #if os(iOS) && canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
            showPlayerStudio.toggle()
        }
    }

    @ViewBuilder
    private func fullBleedArtworkLayer(item: PlaybackItem?, size: CGSize, coverTint: Color) -> some View {
        let artHeight = size.height * 0.64
        ZStack(alignment: .top) {
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: 0)
                .frame(width: size.width, height: artHeight)
                .clipped()
                #if os(iOS)
                .colorEffect(
                    ShaderLibrary.default.mochySeamFade(
                        .float2(CGSize(width: size.width, height: artHeight)),
                        .float(0.46)
                    )
                )
                #else
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.46),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                #endif

            // 1:1 Mochy CoverVeil + ControlsShade for natural readability
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0.0),
                    .init(color: .clear, location: 0.24),
                    .init(color: coverTint.opacity(0.68), location: 0.56),
                    .init(color: .black.opacity(0.55), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onLongPressGesture(minimumDuration: 0.45) {
            togglePlayerStudio()
        }
    }

    @ViewBuilder
    private func coverSection(item: PlaybackItem?, viewport: CGSize) -> some View {
        let baseSide = min(viewport.width - 60, 310)
        let cardSide = max(180, min(viewport.width - 32, baseSide + CGFloat(coordinator.settings.playerCardGrowth)))
        let corner = coordinator.settings.thumbnailCornerRadius

        switch coordinator.settings.playerCoverStyle {
        case .carousel:
            TabView(
                selection: Binding(
                    get: { coordinator.player.currentIndex },
                    set: { idx in coordinator.player.jumpToQueueIndex(idx) }
                )
            ) {
                ForEach(Array(coordinator.player.queue.enumerated()), id: \.offset) { idx, qItem in
                    ArtworkImageView(urlString: qItem.thumbnailURL, cornerRadius: corner)
                        .frame(width: cardSide * 0.92, height: cardSide * 0.92)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                        .tag(idx)
                }
            }
            .frame(height: cardSide)
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

        case .minimal:
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: corner)
                .frame(width: cardSide * 0.72, height: cardSide * 0.72)
                .shadow(color: .black.opacity(0.38), radius: 14, y: 8)

        case .fade, .canvas:
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: corner)
                .frame(width: cardSide, height: cardSide)
                .mask(
                    LinearGradient(
                        colors: [.white, .white, .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

        case .classic, .full:
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: corner)
                .frame(width: cardSide, height: cardSide)
                .scaleEffect(coordinator.player.isPlaying ? 1.0 : 0.92)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: coordinator.player.isPlaying)
                .shadow(color: .black.opacity(0.48), radius: 22, y: 12)
        }
    }

    // 1:1 Mochy 3-button bottom bar: Lyrics · AirPlay (with active route name) · Queue
    private var flagshipBottomBar: some View {
        HStack(alignment: .top) {
            Button(action: onOpenLyrics) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 3) {
                AirPlayRouteButton()
                AudioOutputDeviceLabel()
            }

            Spacer()

            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - WYSIWYG PlayerStudio Overlay (Long-Press Cover/Background)

    private var playerStudioOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Player Studio (Live WYSIWYG)", systemImage: "wand.and.stars")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Done") { showPlayerStudio = false }
                        .font(.caption.bold())
                        .foregroundStyle(MochyTheme.defaultAccent)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlayerCoverStyle.allCases, id: \.self) { style in
                            studioChip(style.rawValue.capitalized, selected: coordinator.settings.playerCoverStyle == style) {
                                coordinator.settings.playerCoverStyle = style
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SeekbarStyle.allCases, id: \.self) { s in
                            studioChip("Bar: \(s.rawValue)", selected: coordinator.settings.seekbarStyle == s) {
                                coordinator.settings.seekbarStyle = s
                            }
                        }
                        ForEach(TransportLayout.allCases, id: \.self) { t in
                            studioChip("Keys: \(t.rawValue)", selected: coordinator.settings.transportLayout == t) {
                                coordinator.settings.transportLayout = t
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FlagshipBackground.allCases, id: \.self) { bg in
                            studioChip(bg.rawValue.replacingOccurrences(of: "_", with: " "), selected: coordinator.settings.flagshipBackground == bg) {
                                coordinator.settings.flagshipBackground = bg
                            }
                        }
                    }
                }

                HStack {
                    Text("Cover Size").font(.caption2).foregroundStyle(.white.opacity(0.75)).frame(width: 78, alignment: .leading)
                    Slider(value: $coordinator.settings.playerCardGrowth, in: -40...45)
                }
                HStack {
                    Text("Corner").font(.caption2).foregroundStyle(.white.opacity(0.75)).frame(width: 78, alignment: .leading)
                    Slider(value: $coordinator.settings.thumbnailCornerRadius, in: 0...36)
                }
                HStack {
                    Text("Controls Y").font(.caption2).foregroundStyle(.white.opacity(0.75)).frame(width: 78, alignment: .leading)
                    Slider(value: $coordinator.settings.playerControlsShift, in: -36...36)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                    .foregroundStyle(MochyTheme.defaultAccent)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 26)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func studioChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.white : Color.white.opacity(0.14))
            .foregroundStyle(selected ? .black : .white)
            .clipShape(Capsule())
    }
}
