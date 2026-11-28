import AVFoundation
import AVKit
import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif
#if os(iOS) && canImport(MediaPlayer)
import MediaPlayer
#endif

// MARK: - Formatting Helper

public enum MochyTimeFormatter {
    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Mochy Seekbar (WAVY / SLIM / DEFAULT — commits seek only on drag end)

public struct MochySeekbarView: View {
    @Bindable public var coordinator: AppCoordinator
    public var accentColor: Color?

    @State private var scrubbingProgress: Double?

    public init(coordinator: AppCoordinator, accentColor: Color? = nil) {
        self.coordinator = coordinator
        self.accentColor = accentColor
    }

    public var body: some View {
        let duration = max(coordinator.player.duration, 1.0)
        let liveProgress = min(1.0, max(0.0, coordinator.player.currentTime / duration))
        let displayProgress = scrubbingProgress ?? liveProgress
        let displayTime = displayProgress * duration
        let accent = accentColor ?? coordinator.paletteColors.first ?? .white

        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height = geo.size.height

                ZStack(alignment: .leading) {
                    switch coordinator.settings.seekbarStyle {
                    case .wavy:
                        wavyTrack(
                            width: width,
                            height: height,
                            progress: displayProgress,
                            accent: accent,
                            isAnimating: coordinator.player.isPlaying && scrubbingProgress == nil
                        )
                    case .slim:
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .frame(height: 3)
                        Capsule()
                            .fill(accent)
                            .frame(width: width * displayProgress, height: 3)
                    case .default:
                        let thumbDiameter: CGFloat = scrubbingProgress != nil ? 14 : 9
                        let trackHeight: CGFloat = scrubbingProgress != nil ? 6 : 4
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .frame(height: trackHeight)
                        Capsule()
                            .fill(accent)
                            .frame(width: max(4, width * displayProgress), height: trackHeight)
                        Circle()
                            .fill(.white)
                            .frame(width: thumbDiameter, height: thumbDiameter)
                            .shadow(color: .black.opacity(0.35), radius: 2.5)
                            .offset(x: max(0, min(width - thumbDiameter, width * displayProgress - thumbDiameter * 0.5)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let ratio = max(0.0, min(1.0, Double(val.location.x / width)))
                            scrubbingProgress = ratio
                        }
                        .onEnded { val in
                            let ratio = max(0.0, min(1.0, Double(val.location.x / width)))
                            scrubbingProgress = nil
                            coordinator.player.seek(to: ratio * duration)
                            #if os(iOS) && canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                )
            }
            .frame(height: 28)

            HStack {
                Text(MochyTimeFormatter.format(displayTime))
                Spacer()
                Text("-\(MochyTimeFormatter.format(max(0, duration - displayTime)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.70))
        }
    }

    private func wavyTrack(
        width: CGFloat,
        height: CGFloat,
        progress: Double,
        accent: Color,
        isAnimating: Bool
    ) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let phase = isAnimating ? timeline.date.timeIntervalSinceReferenceDate * 4.2 : 0.0
            let amp: CGFloat = isAnimating ? 3.4 : 0.0
            let splitX = width * CGFloat(progress)
            let midY = height * 0.5

            Canvas { ctx, _ in
                // Inactive straight track
                var bgPath = Path()
                bgPath.move(to: CGPoint(x: splitX, y: midY))
                bgPath.addLine(to: CGPoint(x: width, y: midY))
                ctx.stroke(bgPath, with: .color(.white.opacity(0.24)), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))

                // Active animated sine wave track
                var wavePath = Path()
                let step: CGFloat = 2.0
                var x: CGFloat = 0
                while x <= splitX {
                    let waveOffset = CGFloat(sin(Double(x) * 0.14 - phase)) * amp
                    let y = midY + waveOffset
                    if x == 0 {
                        wavePath.move(to: CGPoint(x: x, y: y))
                    } else {
                        wavePath.addLine(to: CGPoint(x: x, y: y))
                    }
                    x += step
                }
                ctx.stroke(wavePath, with: .color(accent), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))

                // Playhead pill thumb
                let thumbRect = CGRect(x: max(0, splitX - 2.5), y: midY - 8, width: 5, height: 16)
                ctx.fill(Path(roundedRect: thumbRect, cornerRadius: 2.5), with: .color(.white))
            }
        }
    }
}

// MARK: - Transport Controls Row (THREE / TEN_SECONDS / QUEUE_REPEAT)

public struct TransportControlsRow: View {
    @Bindable public var coordinator: AppCoordinator
    public var onOpenQueue: (() -> Void)?
    public var flagshipMinimal: Bool

    public init(
        coordinator: AppCoordinator,
        onOpenQueue: (() -> Void)? = nil,
        flagshipMinimal: Bool = false
    ) {
        self.coordinator = coordinator
        self.onOpenQueue = onOpenQueue
        self.flagshipMinimal = flagshipMinimal
    }

    public var body: some View {
        HStack(spacing: 22) {
            switch coordinator.settings.transportLayout {
            case .three:
                skipButton(systemName: "backward.fill") { coordinator.player.skipPrevious() }
                playPauseCapsule
                skipButton(systemName: "forward.fill") { coordinator.player.skipNext() }

            case .tenSeconds:
                smallButton(systemName: "gobackward.10") {
                    coordinator.player.seek(to: max(0, coordinator.player.currentTime - 10))
                }
                skipButton(systemName: "backward.fill") { coordinator.player.skipPrevious() }
                playPauseCapsule
                skipButton(systemName: "forward.fill") { coordinator.player.skipNext() }
                smallButton(systemName: "goforward.10") {
                    coordinator.player.seek(to: coordinator.player.currentTime + 10)
                }

            case .queueRepeat:
                smallButton(
                    systemName: "shuffle",
                    active: coordinator.player.shuffleEnabled
                ) {
                    coordinator.player.shuffleEnabled.toggle()
                }
                skipButton(systemName: "backward.fill") { coordinator.player.skipPrevious() }
                playPauseCapsule
                skipButton(systemName: "forward.fill") { coordinator.player.skipNext() }
                smallButton(
                    systemName: coordinator.player.repeatMode == .one ? "repeat.1" : "repeat",
                    active: coordinator.player.repeatMode != .off
                ) {
                    cycleRepeatMode()
                }
            }
        }
    }

    private var playPauseCapsule: some View {
        Button {
            coordinator.player.togglePlayPause()
            #if os(iOS) && canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        } label: {
            ZStack {
                if !flagshipMinimal {
                    Circle()
                        .fill(.white)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
                }
                if coordinator.player.isBuffering {
                    ProgressView().tint(flagshipMinimal ? .white : .black)
                } else {
                    Image(systemName: coordinator.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: flagshipMinimal ? 38 : 27, weight: .bold))
                        .foregroundStyle(flagshipMinimal ? .white : .black)
                        .offset(x: coordinator.player.isPlaying ? 0 : 2)
                }
            }
            .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
    }

    private func skipButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: flagshipMinimal ? 30 : 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private func smallButton(systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.68))
                .frame(width: 36, height: 36)
                .background(active ? Color.white.opacity(0.14) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func cycleRepeatMode() {
        switch coordinator.player.repeatMode {
        case .off: coordinator.player.repeatMode = .all
        case .all: coordinator.player.repeatMode = .one
        case .one: coordinator.player.repeatMode = .off
        }
    }
}

// MARK: - LikeBurstButton (Backed by Real DB State + Particle Burst)

public struct LikeBurstButton: View {
    @Bindable public var coordinator: AppCoordinator
    public let songId: String
    @State private var burstScale: CGFloat = 0.2
    @State private var burstOpacity: Double = 0

    public init(coordinator: AppCoordinator, songId: String) {
        self.coordinator = coordinator
        self.songId = songId
    }

    public var body: some View {
        let liked = coordinator.isLiked(songId: songId)
        Button {
            coordinator.toggleLike(songId: songId)
            if !liked {
                burstScale = 0.35
                burstOpacity = 1.0
                withAnimation(.easeOut(duration: 0.45)) {
                    burstScale = 1.85
                    burstOpacity = 0.0
                }
            }
            #if os(iOS) && canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        } label: {
            ZStack {
                ForEach(0..<8, id: \.self) { idx in
                    let angle = Double(idx) * (.pi / 4.0)
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 4, height: 4)
                        .offset(
                            x: CGFloat(cos(angle)) * 16 * burstScale,
                            y: CGFloat(sin(angle)) * 16 * burstScale
                        )
                        .opacity(burstOpacity)
                }

                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(liked ? .white : .white.opacity(0.75))
                    .scaleEffect(liked ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: liked)
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TurntablePills (Used by Turntable & Poster Styles)

public struct TurntablePills: View {
    @Bindable public var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 10) {
            pillButton(icon: "backward.fill", width: 48) {
                coordinator.player.skipPrevious()
            }
            pillButton(icon: coordinator.player.isPlaying ? "pause.fill" : "play.fill", width: 72, prominent: true) {
                coordinator.player.togglePlayPause()
            }
            pillButton(icon: "forward.fill", width: 48) {
                coordinator.player.skipNext()
            }
        }
    }

    private func pillButton(icon: String, width: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 20 : 16, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: width, height: 46)
                .background(prominent ? Color.white : Color.white.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.16), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TransportCircles (Used by Timeline & Lyrics Styles)

public struct TransportCircles: View {
    @Bindable public var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 18) {
            circleBtn("backward.fill", size: 48, primary: false) {
                coordinator.player.skipPrevious()
            }
            circleBtn(coordinator.player.isPlaying ? "pause.fill" : "play.fill", size: 62, primary: true) {
                coordinator.player.togglePlayPause()
            }
            circleBtn("forward.fill", size: 48, primary: false) {
                coordinator.player.skipNext()
            }
        }
    }

    private func circleBtn(_ icon: String, size: CGFloat, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: primary ? 24 : 18, weight: .bold))
                .foregroundStyle(primary ? .black : .white)
                .frame(width: size, height: size)
                .background(primary ? Color.white : Color.black.opacity(0.32))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(primary ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CoverRingView (Arc Progress + Radial Real vDSP FFT Visualizer)

public struct CoverRingView: View {
    public let progress: Double
    public let spectrumBins: [Float]
    public let showVisualizer: Bool
    public let accent: Color

    public init(progress: Double, spectrumBins: [Float], showVisualizer: Bool, accent: Color) {
        self.progress = progress
        self.spectrumBins = spectrumBins
        self.showVisualizer = showVisualizer
        self.accent = accent
    }

    public var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = min(size.width, size.height) * 0.5 - 10

            // Base hairline ring
            let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.18)), lineWidth: 2.5)

            // Progress arc
            var arc = Path()
            let endAngle = Angle.degrees(-90 + 360 * min(1, max(0, progress)))
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: endAngle, clockwise: false)
            ctx.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Radial FFT visualizer spikes
            if showVisualizer && !spectrumBins.isEmpty {
                let count = min(32, spectrumBins.count)
                for i in 0..<count {
                    let angle = (Double(i) / Double(count)) * (Double.pi * 2.0) - Double.pi * 0.5
                    let cosA = CGFloat(cos(angle))
                    let sinA = CGFloat(sin(angle))
                    let mag = CGFloat(min(Float(1.0), max(Float(0.0), spectrumBins[i])))
                    let barLen: CGFloat = 4.0 + mag * 26.0
                    let r0: CGFloat = radius + 4.0
                    let r1: CGFloat = r0 + barLen
                    var p = Path()
                    p.move(to: CGPoint(x: center.x + cosA * r0, y: center.y + sinA * r0))
                    p.addLine(to: CGPoint(x: center.x + cosA * r1, y: center.y + sinA * r1))
                    let opacityVal = 0.45 + Double(mag) * 0.55
                    ctx.stroke(p, with: .color(accent.opacity(opacityVal)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - RidingTimesLayout (1:1 Mochy Two-Tone Fullscreen Progress Split + Riding Timestamps)

public struct RidingTimesLayout<HeaderContent: View>: View {
    @Bindable public var coordinator: AppCoordinator
    public let headerContent: () -> HeaderContent

    @State private var dragProgress: Double?

    public init(coordinator: AppCoordinator, @ViewBuilder headerContent: @escaping () -> HeaderContent) {
        self.coordinator = coordinator
        self.headerContent = headerContent
    }

    public var body: some View {
        let duration = max(coordinator.player.duration, 1.0)
        let livePct = min(1.0, max(0.0, coordinator.player.currentTime / duration))
        let pct = dragProgress ?? livePct
        let accent = coordinator.paletteColors.first ?? Color(white: 0.26)
        let c1 = coordinator.paletteColors.indices.contains(1) ? coordinator.paletteColors[1] : Color(white: 0.15)

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minY = h * 0.24
            let maxY = h * 0.78
            let splitY = minY + (maxY - minY) * CGFloat(pct)

            ZStack(alignment: .top) {
                // Upper surface (elapsed zone)
                LinearGradient(colors: [accent.opacity(0.88), c1.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                // Lower surface (remaining zone) moving down with progress
                Color.black.opacity(0.86)
                    .frame(height: max(0, h - splitY + 80))
                    .offset(y: splitY)

                // Crisp moving playhead line
                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(height: 2)
                    .offset(y: splitY)

                // Riding Bold Timestamps straddling the playhead line
                HStack(alignment: .firstTextBaseline) {
                    Text(MochyTimeFormatter.format(pct * duration))
                        .font(.system(size: min(68, w * 0.16), weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Spacer()
                    Text("-\(MochyTimeFormatter.format(max(0, duration - pct * duration)))")
                        .font(.system(size: min(44, w * 0.105), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.horizontal, 20)
                .offset(y: max(minY - 40, splitY - 58))

                // Top Header + Bottom Controls overlay
                VStack(alignment: .leading) {
                    headerContent()
                        .padding(.top, 64)
                        .padding(.horizontal, 22)
                    Spacer()
                    HStack {
                        Spacer()
                        TransportCircles(coordinator: coordinator)
                        Spacer()
                    }
                    .padding(.bottom, 36)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { val in
                        let normalized = (val.location.y - minY) / max(1, maxY - minY)
                        dragProgress = Double(max(0, min(1, normalized)))
                    }
                    .onEnded { val in
                        let normalized = (val.location.y - minY) / max(1, maxY - minY)
                        let clamped = Double(max(0, min(1, normalized)))
                        dragProgress = nil
                        coordinator.player.seek(to: clamped * duration)
                    }
            )
        }
    }
}

// MARK: - AirPlay Route Picker Button

public struct AirPlayRouteButton: View {
    public init() {}

    public var body: some View {
        #if os(iOS) && canImport(UIKit)
        AirPlayRoutePickerRepresentable()
            .frame(width: 30, height: 30)
        #else
        Image(systemName: "airplayaudio")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 30, height: 30)
        #endif
    }
}

#if os(iOS) && canImport(UIKit)
private struct AirPlayRoutePickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(MochyTheme.defaultAccent)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Marquee Title / Artist Text

public struct MochyMarqueeText: View {
    public let text: String
    public let font: Font
    public let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0

    public init(_ text: String, font: Font, color: Color = .white) {
        self.text = text
        self.font = font
        self.color = color
    }

    public var body: some View {
        let shouldScroll = textWidth > containerWidth + 8 && containerWidth > 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .onAppear { textWidth = inner.size.width }
                                .onChange(of: text) { _, _ in
                                    textWidth = inner.size.width
                                    offsetX = 0
                                }
                        }
                    )
                    .offset(x: shouldScroll ? offsetX : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, newW in containerWidth = newW }
        }
        .frame(height: 26)
        .task(id: "\(text)-\(Int(textWidth))-\(Int(containerWidth))") {
            offsetX = 0
            guard textWidth > containerWidth + 8, containerWidth > 0 else { return }
            let delta = -(textWidth - containerWidth + 16)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: Double(abs(delta)) / 28.0)) {
                    offsetX = delta
                }
                try? await Task.sleep(for: .seconds(Double(abs(delta)) / 28.0 + 1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    offsetX = 0
                }
            }
        }
    }
}

// MARK: - Apple Music Slim Volume Bar (Bridged to System Audio Volume on iOS)

public struct MochyVolumeBar: View {
    @State private var volume: Double = 0.65
    @State private var isDragging = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let trackHeight: CGFloat = isDragging ? 9 : 4.5
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: max(4, width * volume), height: trackHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isDragging = true
                            let pct = max(0.0, min(1.0, Double(val.location.x / width)))
                            volume = pct
                            setSystemVolume(Float(pct))
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.18)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: 22)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .onAppear {
            volume = Double(currentSystemVolume())
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AVSystemController_SystemVolumeDidChangeNotification"))) { _ in
            if !isDragging {
                volume = Double(currentSystemVolume())
            }
        }
        #endif
    }

    private func currentSystemVolume() -> Float {
        #if os(iOS)
        return AVAudioSession.sharedInstance().outputVolume
        #else
        return Float(volume)
        #endif
    }

    private func setSystemVolume(_ value: Float) {
        #if os(iOS) && canImport(MediaPlayer) && canImport(UIKit)
        SystemVolumeBridge.shared.setVolume(value)
        #endif
    }
}

#if os(iOS) && canImport(MediaPlayer) && canImport(UIKit)
@MainActor
private final class SystemVolumeBridge {
    static let shared = SystemVolumeBridge()
    private let volumeView = MPVolumeView(frame: .zero)

    func setVolume(_ value: Float) {
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                slider.value = value
            }
        }
    }
}
#endif

// MARK: - Active Audio Output Device Label

public struct AudioOutputDeviceLabel: View {
    @State private var portName: String = "Speakers"

    public init() {}

    public var body: some View {
        Text(portName)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .onAppear { refreshRoute() }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                refreshRoute()
            }
            #endif
    }

    private func refreshRoute() {
        #if os(iOS)
        if let output = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            portName = output.portType == .builtInSpeaker ? "iPhone" : output.portName
        } else {
            portName = "iPhone"
        }
        #else
        portName = "Mac Audio"
        #endif
    }
}
