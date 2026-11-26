import MochyAudio
import MochyCore
import SwiftUI

/// 1:1 Mochy `PosterPlayerStyle`:
/// - Giant off-center top-left circular cover (`center = (0.13W, 0.06W)`, `radius = 1.14W`)
/// - `CoverRingView` along the circular rim (tap to toggle radial FFT bars)
/// - Expressive oversized synced lyrics (`32..44pt`) + credit lines + `TurntablePills` bottom-right
public struct PosterPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenLyrics: () -> Void

    @State private var showVisualizerRing = true

    public var body: some View {
        let item = coordinator.player.currentItem
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent
        let duration = max(coordinator.player.duration, 1.0)
        let progress = min(1.0, max(0.0, coordinator.player.currentTime / duration))
        let liveLyric = coordinator.activeLyricLineText()

        GeometryReader { geo in
            let w = geo.size.width
            let diameter = w * 1.14
            let centerX = w * 0.13
            let centerY = w * 0.06

            ZStack(alignment: .bottomLeading) {
                AmbientBackdropView(
                    colors: coordinator.paletteColors,
                    style: .darkGradient,
                    blurQuality: coordinator.settings.blurQuality,
                    isPaused: !coordinator.player.isPlaying
                )

                // Giant off-center top-left circular cover + CoverRing
                ZStack {
                    ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: diameter * 0.5)
                        .frame(width: diameter - 20, height: diameter - 20)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.60), radius: 24, y: 12)

                    CoverRingView(
                        progress: progress,
                        spectrumBins: coordinator.player.spectrumBins,
                        showVisualizer: showVisualizerRing,
                        accent: accent
                    )
                    .frame(width: diameter, height: diameter)
                }
                .position(x: centerX, y: centerY + diameter * 0.34)
                .onTapGesture {
                    showVisualizerRing.toggle()
                }

                // Editorial Poster foreground
                VStack(alignment: .leading, spacing: 18) {
                    Spacer()

                    Button(action: onOpenLyrics) {
                        Text(liveLyric.isEmpty ? (item?.title ?? "Natch Music") : liveLyric)
                            .font(.system(size: min(40, w * 0.095), weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .minimumScaleFactor(0.72)
                            .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text((item?.title ?? "").uppercased())
                            .font(.caption.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                        Text(item?.artist ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }

                    MochySeekbarView(coordinator: coordinator, accentColor: accent)

                    HStack {
                        if let id = item?.id {
                            LikeBurstButton(coordinator: coordinator, songId: id)
                        }
                        Spacer()
                        TurntablePills(coordinator: coordinator)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 28))
            }
            .clipped()
        }
    }
}
