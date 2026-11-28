import MochyAudio
import MochyCore
import SwiftUI

public struct FlagshipPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public var coverNamespace: Namespace.ID
    @Binding public var showPlayerStudio: Bool
    public let onOpenLyrics: () -> Void
    public let onOpenQueue: () -> Void
    public let onOpenAudioLab: () -> Void
    public let onOpenShare: () -> Void
    public let onOpenStreamInfo: () -> Void

    public var body: some View {
        let item = coordinator.player.currentItem

        GeometryReader { geo in
            ZStack {
                AmbientBackdropView(
                    colors: coordinator.paletteColors,
                    style: coordinator.settings.flagshipBackground,
                    blurQuality: coordinator.settings.blurQuality,
                    isPaused: !coordinator.player.isPlaying
                )

                if coordinator.settings.playerCoverStyle == .full {
                    fullBleedArtworkLayer(item: item, size: geo.size)
                }

                VStack(spacing: 16) {
                    Spacer(minLength: coordinator.settings.playerCoverStyle == .full ? geo.size.height * 0.36 : 86)

                    if coordinator.settings.playerCoverStyle != .full {
                        coverSection(item: item, viewport: geo.size)
                    }

                    // Track metadata + real LikeBurstButton
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item?.title ?? "Not Playing")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item?.artist ?? "Select a track")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        Spacer()
                        if let id = item?.id {
                            LikeBurstButton(coordinator: coordinator, songId: id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, CGFloat(coordinator.settings.playerControlsShift) * 0.3)

                    MochySeekbarView(coordinator: coordinator, accentColor: .white.opacity(0.92))
                        .padding(.horizontal, 24)

                    if let err = coordinator.player.lastError, !err.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                onOpenStreamInfo()
                            } label: {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
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
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                    }

                    TransportControlsRow(coordinator: coordinator, onOpenQueue: onOpenQueue)
                        .padding(.vertical, 6)

                    flagshipBottomBar
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 22))
                }
                .offset(y: CGFloat(coordinator.settings.playerControlsShift))

                if showPlayerStudio {
                    playerStudioOverlay
                }
            }
        }
    }

    @ViewBuilder
    private func fullBleedArtworkLayer(item: PlaybackItem?, size: CGSize) -> some View {
        VStack(spacing: 0) {
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: 0)
                .frame(width: size.width, height: size.height * 0.60)
                .clipped()
                #if os(iOS)
                .colorEffect(
                    ShaderLibrary.default.mochySeamFade(
                        .float2(CGSize(width: size.width, height: size.height * 0.60)),
                        .float(0.52)
                    )
                )
                #else
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.52),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                #endif
            Spacer()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func coverSection(item: PlaybackItem?, viewport: CGSize) -> some View {
        let baseSide = min(viewport.width - 56, 330)
        let cardSide = max(180, min(viewport.width - 28, baseSide + CGFloat(coordinator.settings.playerCardGrowth)))
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
                .matchedGeometryEffect(id: "activeCoverArt", in: coverNamespace, isSource: coordinator.isPlayerExpanded)

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
                .matchedGeometryEffect(id: "activeCoverArt", in: coverNamespace, isSource: coordinator.isPlayerExpanded)

        case .classic, .full:
            ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: corner)
                .frame(width: cardSide, height: cardSide)
                .scaleEffect(coordinator.player.isPlaying ? 1.0 : 0.92)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: coordinator.player.isPlaying)
                .shadow(color: .black.opacity(0.48), radius: 22, y: 12)
                .matchedGeometryEffect(id: "activeCoverArt", in: coverNamespace, isSource: coordinator.isPlayerExpanded)
        }
    }

    private var flagshipBottomBar: some View {
        HStack {
            bottomToolButton("quote.bubble", label: "Lyrics", action: onOpenLyrics)
            Spacer()
            bottomToolButton("slider.vertical.3", label: "Audio Lab", action: onOpenAudioLab)
            Spacer()
            VStack(spacing: 4) {
                AirPlayRouteButton()
                Text("AirPlay").font(.caption2).foregroundStyle(.white.opacity(0.70))
            }
            Spacer()
            bottomToolButton("list.bullet", label: "Queue", action: onOpenQueue)
            Spacer()
            bottomToolButton("square.and.arrow.up", label: "Share", action: onOpenShare)
        }
    }

    private func bottomToolButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(height: 30)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - WYSIWYG PlayerStudio Overlay

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
