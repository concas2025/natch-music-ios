import MochyAudio
import MochyCore
import SwiftUI

/// 1:1 Mochy `TimelinePlayerStyle`:
/// Square mini-cover + crisp title/artist header over full-screen `RidingTimesLayout` + `TransportCircles`.
public struct TimelinePlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        let item = coordinator.player.currentItem
        RidingTimesLayout(coordinator: coordinator) {
            HStack(spacing: 14) {
                ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: 12)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item?.title ?? "Timeline")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1)
                }
                Spacer()
                if let id = item?.id {
                    LikeBurstButton(coordinator: coordinator, songId: id)
                }
            }
            .padding(.top, 36)
        }
    }
}

/// 1:1 Mochy `LyricsPlayerStyle`:
/// Giant expressive synced lyric headline over full-screen `RidingTimesLayout` + `TransportCircles`.
public struct LyricsStylePlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenFullLyrics: () -> Void

    public var body: some View {
        let item = coordinator.player.currentItem
        let liveLyric = coordinator.activeLyricLineText()

        RidingTimesLayout(coordinator: coordinator) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpenFullLyrics) {
                    Text(liveLyric.isEmpty ? (item?.title ?? "Synced Lyrics") : liveLyric)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.70)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Text(item?.title ?? "")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.55))
                    Text(item?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
            }
            .padding(.top, 36)
        }
    }
}
