import AVFoundation
import AVKit
import MochyAudio
import MochyCore
import MochyInnerTube
import SwiftUI

/// Synchronized Music Video Player Style:
/// - Loads `YTVideoStreamOption` with `AVURLAssetHTTPHeaderFieldsKey`
/// - Mutes video track (audio continues through `MochyAudioPlayer`'s C++ DSP pipeline)
/// - Keeps Play/Pause/Rate and timestamp tightly locked (`abs(drift) > 0.35s`)
/// - Cleans up `AVPlayer` on `.onDisappear`
public struct VideoPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenLyrics: () -> Void
    public let onOpenQueue: () -> Void

    @State private var videoPlayer: AVPlayer?
    @State private var selectedItag: Int?
    @State private var showFloatingLyrics = true
    @State private var isLoadingStreams = false

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoPlayer {
                AVVideoLayerView(player: videoPlayer)
                    .ignoresSafeArea()
            } else {
                ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 0)
                    .ignoresSafeArea()
                    .blur(radius: 26)
                    .overlay(Color.black.opacity(0.55))
            }

            // Vignette gradient for crisp readability
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                if isLoadingStreams && videoPlayer == nil {
                    ProgressView("Loading synchronized video...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.85))
                } else if videoPlayer == nil && !isLoadingStreams {
                    Text("No video stream available for this track.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                }

                if showFloatingLyrics {
                    let line = coordinator.activeLyricLineText()
                    if !line.isEmpty {
                        Text(line)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.85), radius: 8, y: 2)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                    }
                }

                // Track info + quality selector
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coordinator.player.currentItem?.title ?? "")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(coordinator.player.currentItem?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()

                    if !coordinator.videoStreamOptions.isEmpty {
                        Menu {
                            ForEach(coordinator.videoStreamOptions) { opt in
                                Button {
                                    selectedItag = opt.itag
                                    attachStream(opt)
                                } label: {
                                    HStack {
                                        Text("\(opt.qualityLabel) (\(opt.width)x\(opt.height))")
                                        if selectedItag == opt.itag {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            let label = coordinator.videoStreamOptions.first(where: { $0.itag == selectedItag })?.qualityLabel ?? "HD"
                            Text(label)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.20))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Button {
                        showFloatingLyrics.toggle()
                    } label: {
                        Image(systemName: showFloatingLyrics ? "captions.bubble.fill" : "captions.bubble")
                            .foregroundStyle(showFloatingLyrics ? MochyTheme.defaultAccent : .white.opacity(0.75))
                            .frame(width: 34, height: 34)
                    }
                }
                .padding(.horizontal, 22)

                MochySeekbarView(coordinator: coordinator)
                    .padding(.horizontal, 22)

                TransportControlsRow(coordinator: coordinator, onOpenQueue: onOpenQueue)

                HStack(spacing: 32) {
                    Button(action: onOpenLyrics) {
                        Label("Lyrics Stage", systemImage: "quote.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Button(action: onOpenQueue) {
                        Label("Queue", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            }
        }
        .task(id: coordinator.player.currentItem?.id) {
            await loadStreamsForCurrentTrack()
        }
        .onChange(of: coordinator.player.isPlaying) { _, playing in
            syncVideoPlaybackState(isPlaying: playing)
        }
        .onChange(of: coordinator.player.currentTime) { _, audioSecs in
            syncVideoClock(audioSeconds: audioSecs)
        }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer?.replaceCurrentItem(with: nil)
            videoPlayer = nil
        }
    }

    private func loadStreamsForCurrentTrack() async {
        videoPlayer?.pause()
        videoPlayer = nil
        isLoadingStreams = true
        defer { isLoadingStreams = false }

        await coordinator.loadVideoStreamsForCurrent()
        // Pick crisp 720p/1080p default (or highest progressive)
        let preferred = coordinator.videoStreamOptions.first(where: { $0.height == 720 || $0.height == 1080 })
            ?? coordinator.videoStreamOptions.first
        if let preferred {
            selectedItag = preferred.itag
            attachStream(preferred)
        }
    }

    private func attachStream(_ option: YTVideoStreamOption) {
        videoPlayer?.pause()
        var assetOptions: [String: Any] = [:]
        if !option.headers.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = option.headers
        }
        let asset = AVURLAsset(url: option.url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        let av = AVPlayer(playerItem: item)
        av.isMuted = true
        av.actionAtItemEnd = .none
        let target = CMTime(seconds: coordinator.player.currentTime, preferredTimescale: 600)
        av.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if coordinator.player.isPlaying {
            av.play()
            av.rate = coordinator.player.playbackSpeed
        }
        videoPlayer = av
    }

    private func syncVideoPlaybackState(isPlaying: Bool) {
        guard let videoPlayer else { return }
        if isPlaying {
            videoPlayer.play()
            videoPlayer.rate = coordinator.player.playbackSpeed
        } else {
            videoPlayer.pause()
        }
    }

    private func syncVideoClock(audioSeconds: TimeInterval) {
        guard let videoPlayer, audioSeconds.isFinite else { return }
        let videoSecs = videoPlayer.currentTime().seconds
        if !videoSecs.isFinite || abs(videoSecs - audioSeconds) > 0.35 {
            let target = CMTime(seconds: audioSeconds, preferredTimescale: 600)
            videoPlayer.seek(to: target, toleranceBefore: CMTime(seconds: 0.15, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.15, preferredTimescale: 600))
        }
    }
}

#if os(iOS) && canImport(UIKit)
private struct AVVideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerLayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
#else
private struct AVVideoLayerView: View {
    let player: AVPlayer
    var body: some View {
        VideoPlayer(player: player)
    }
}
#endif
