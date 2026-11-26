import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public struct TurntablePlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenLyrics: () -> Void
    public let onOpenQueue: () -> Void
    public let onOpenAudioLab: () -> Void

    @State private var armScrubProgress: Double?
    @State private var lastTickStep: Int = -1

    public var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                AmbientBackdropView(
                    colors: coordinator.paletteColors,
                    style: .darkGradient,
                    blurQuality: coordinator.settings.blurQuality,
                    isPaused: !coordinator.player.isPlaying
                )

                if isLandscape {
                    HStack(spacing: 24) {
                        vinylDeck(diameter: min(geo.size.height * 0.78, geo.size.width * 0.44))
                            .frame(maxWidth: .infinity)
                        controlsColumn
                            .frame(maxWidth: .infinity)
                            .padding(.trailing, 24)
                    }
                    .padding(.top, 52)
                } else {
                    VStack(spacing: 22) {
                        Spacer(minLength: 74)
                        vinylDeck(diameter: min(geo.size.width * 0.80, 320))
                        controlsColumn
                            .padding(.horizontal, 24)
                        Spacer(minLength: 26)
                    }
                }
            }
        }
    }

    private func vinylDeck(diameter: CGFloat) -> some View {
        let duration = max(coordinator.player.duration, 1.0)
        let livePct = min(1.0, max(0.0, coordinator.player.currentTime / duration))
        let pct = armScrubProgress ?? livePct
        let isEngaged = coordinator.player.isPlaying || armScrubProgress != nil
        let armAngle = isEngaged ? (14.0 + pct * 24.0) : 2.0

        return ZStack(alignment: .topTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !coordinator.player.isPlaying)) { timeline in
                let rpmAngle = coordinator.player.isPlaying
                    ? (timeline.date.timeIntervalSinceReferenceDate * 42.0).truncatingRemainder(dividingBy: 360)
                    : 0
                vinylDisc(diameter: diameter, rotationDegrees: rpmAngle)
            }
            .frame(width: diameter, height: diameter)
            .padding(.trailing, diameter * 0.10)

            TurntableArmView(angleDegrees: armAngle, armLength: diameter * 0.72)
                .frame(width: diameter * 0.34, height: diameter * 0.86)
                .offset(x: 10, y: -6)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isEngaged)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { val in
                            let ratio = max(0, min(1, Double((val.location.y) / max(1, diameter * 0.68))))
                            armScrubProgress = ratio
                            let step = Int(ratio * 24)
                            if step != lastTickStep {
                                lastTickStep = step
                                #if os(iOS) && canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }
                        }
                        .onEnded { val in
                            let ratio = max(0, min(1, Double((val.location.y) / max(1, diameter * 0.68))))
                            armScrubProgress = nil
                            coordinator.player.seek(to: ratio * duration)
                        }
                )
        }
    }

    private func vinylDisc(diameter: CGFloat, rotationDegrees: Double) -> some View {
        ZStack {
            // Platter metallic rim
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.24), Color(white: 0.06)],
                        center: .center,
                        startRadius: diameter * 0.46,
                        endRadius: diameter * 0.51
                    )
                )

            // Main vinyl body + grooves
            Circle()
                .fill(Color(white: 0.05))
                .padding(5)
                .overlay {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        let rMax = min(size.width, size.height) * 0.47
                        for step in stride(from: rMax * 0.44, through: rMax, by: 4.0) {
                            let rect = CGRect(x: c.x - step, y: c.y - step, width: step * 2, height: step * 2)
                            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.06)), lineWidth: 0.7)
                        }
                    }
                }
                .overlay(
                    AngularGradient(
                        colors: [.clear, .white.opacity(0.11), .clear, .white.opacity(0.08), .clear],
                        center: .center
                    )
                    .clipShape(Circle())
                    .padding(6)
                )

            // Rotating center artwork label
            ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: diameter * 0.22)
                .frame(width: diameter * 0.40, height: diameter * 0.40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 3))
                .rotationEffect(.degrees(rotationDegrees))

            // Spindle pin
            Circle()
                .fill(Color(white: 0.78))
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.65), radius: 22, y: 12)
    }

    private var controlsColumn: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(coordinator.player.currentItem?.title ?? "Turntable")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(coordinator.player.currentItem?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }

            MochySeekbarView(coordinator: coordinator)

            TurntablePills(coordinator: coordinator)

            HStack(spacing: 28) {
                Button(action: onOpenLyrics) {
                    Label("Lyrics", systemImage: "quote.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button(action: onOpenAudioLab) {
                    Label("Audio Lab", systemImage: "slider.vertical.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Button(action: onOpenQueue) {
                    Label("Queue", systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

/// Custom curved S-tonearm drawn with SwiftUI `Canvas` & `Path` (gimbal pivot, counterweight, S-arm, headshell).
public struct TurntableArmView: View {
    public let angleDegrees: Double
    public let armLength: CGFloat

    public var body: some View {
        Canvas { ctx, size in
            let pivot = CGPoint(x: size.width * 0.62, y: 28)

            // Gimbal housing
            let housingRect = CGRect(x: pivot.x - 19, y: pivot.y - 19, width: 38, height: 38)
            ctx.fill(Path(ellipseIn: housingRect), with: .color(Color(white: 0.24)))
            ctx.stroke(Path(ellipseIn: housingRect), with: .color(.white.opacity(0.32)), lineWidth: 1.5)

            // Rotate S-arm around pivot
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: .degrees(angleDegrees))

            // Counterweight cylinder behind pivot
            let cwRect = CGRect(x: -7, y: -26, width: 14, height: 14)
            ctx.fill(Path(roundedRect: cwRect, cornerRadius: 3), with: .color(Color(white: 0.45)))

            // Curved S-arm tube
            var armPath = Path()
            armPath.move(to: CGPoint(x: 0, y: -12))
            armPath.addLine(to: CGPoint(x: 0, y: armLength * 0.56))
            armPath.addCurve(
                to: CGPoint(x: -24, y: armLength * 0.94),
                control1: CGPoint(x: 0, y: armLength * 0.74),
                control2: CGPoint(x: -14, y: armLength * 0.84)
            )
            ctx.stroke(armPath, with: .color(Color(white: 0.82)), style: StrokeStyle(lineWidth: 5.0, lineCap: .round))
            ctx.stroke(armPath, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Headshell + cartridge
            let headRect = CGRect(x: -34, y: armLength * 0.90, width: 14, height: 24)
            ctx.fill(Path(roundedRect: headRect, cornerRadius: 3), with: .color(Color(white: 0.16)))
            ctx.stroke(Path(roundedRect: headRect, cornerRadius: 3), with: .color(MochyTheme.defaultAccent), lineWidth: 1.2)

            // Pivot cap screw
            ctx.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(Color(white: 0.76)))
        }
    }
}
