import MochyAudio
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// 1:1 Mochy `BedsidePlayerStyle`:
/// - All 4 `BedsideClockStyle`s (`BIG`, `STACKED`, `ANALOG`, `COVER`)
/// - Warm amber OLED night tint (`bedsideNightTint`)
/// - Vertical swipe dimmer overlay (`0.0...0.78`)
/// - Subtle OLED burn-in pixel shift every 30s + `isIdleTimerDisabled = true` while visible
public struct BedsidePlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var dimOpacity: Double = 0.0

    public var body: some View {
        let tint: Color = coordinator.settings.bedsideNightTint
            ? Color(red: 1.0, green: 0.62, blue: 0.24)
            : .white

        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let now = timeline.date
            let shiftSlot = Int(now.timeIntervalSince1970 / 30.0) % 4
            let pixelShift = CGSize(
                width: shiftSlot == 1 ? 3 : (shiftSlot == 3 ? -3 : 0),
                height: shiftSlot == 2 ? 3 : (shiftSlot == 0 ? -3 : 0)
            )

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer(minLength: 82)

                    clockDisplay(date: now, tint: tint)
                        .offset(pixelShift)
                        .animation(.easeInOut(duration: 1.0), value: shiftSlot)

                    // Style & Night Tint quick switch strip
                    HStack(spacing: 8) {
                        ForEach(BedsideClockStyle.allCases, id: \.self) { style in
                            let selected = coordinator.settings.bedsideClockStyle == style
                            Button(style.rawValue.capitalized) {
                                coordinator.settings.bedsideClockStyle = style
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selected ? tint.opacity(0.26) : Color.white.opacity(0.08))
                            .foregroundStyle(selected ? tint : .white.opacity(0.60))
                            .clipShape(Capsule())
                        }
                        Button {
                            coordinator.settings.bedsideNightTint.toggle()
                        } label: {
                            Image(systemName: coordinator.settings.bedsideNightTint ? "moon.fill" : "sun.max.fill")
                                .font(.caption)
                                .foregroundStyle(tint)
                                .padding(7)
                                .background(.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }

                    VStack(spacing: 4) {
                        Text(coordinator.player.currentItem?.title ?? "Bedside")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(tint.opacity(0.92))
                            .lineLimit(1)
                        Text(coordinator.player.currentItem?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(tint.opacity(0.62))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 34) {
                        Button { coordinator.player.skipPrevious() } label: {
                            Image(systemName: "backward.fill").font(.title3).foregroundStyle(tint.opacity(0.8))
                        }
                        Button { coordinator.player.togglePlayPause() } label: {
                            Image(systemName: coordinator.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(tint)
                        }
                        Button { coordinator.player.skipNext() } label: {
                            Image(systemName: "forward.fill").font(.title3).foregroundStyle(tint.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)

                    Text("Swipe up/down to dim (\(Int((1 - dimOpacity) * 100))%)")
                        .font(.caption2)
                        .foregroundStyle(tint.opacity(0.38))

                    Spacer(minLength: 26)
                }

                // Vertical swipe dimmer veil
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { val in
                        if abs(val.translation.height) > abs(val.translation.width) {
                            let delta = Double(val.translation.height) / 360.0
                            dimOpacity = max(0.0, min(0.78, dimOpacity + delta * 0.12))
                        }
                    }
            )
        }
        .onAppear {
            #if os(iOS) && canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS) && canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }

    @ViewBuilder
    private func clockDisplay(date: Date, tint: Color) -> some View {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hh = String(format: "%02d", comps.hour ?? 0)
        let mm = String(format: "%02d", comps.minute ?? 0)

        switch coordinator.settings.bedsideClockStyle {
        case .big:
            Text("\(hh):\(mm)")
                .font(.system(size: 96, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)

        case .stacked:
            VStack(spacing: -18) {
                Text(hh)
                    .font(.system(size: 108, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(mm)
                    .font(.system(size: 108, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.78)
            }
            .foregroundStyle(tint)

        case .analog:
            analogClock(hour: comps.hour ?? 0, minute: comps.minute ?? 0, second: comps.second ?? 0, tint: tint)
                .frame(width: 210, height: 210)

        case .cover:
            VStack(spacing: 14) {
                ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 20)
                    .frame(width: 176, height: 176)
                    .saturation(coordinator.settings.bedsideNightTint ? 0.35 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    )
                Text("\(hh):\(mm)")
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
    }

    private func analogClock(hour: Int, minute: Int, second: Int, tint: Color) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.46

            // Bezel & 12 hour ticks
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(tint.opacity(0.30)), lineWidth: 2)
            for tick in 0..<12 {
                let angle = Double(tick) * (.pi / 6) - .pi * 0.5
                let inner = r - (tick % 3 == 0 ? 14 : 8)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(angle) * (r - 2), y: c.y + sin(angle) * (r - 2)))
                ctx.stroke(p, with: .color(tint.opacity(tick % 3 == 0 ? 0.85 : 0.4)), style: StrokeStyle(lineWidth: tick % 3 == 0 ? 2.5 : 1.2, lineCap: .round))
            }

            let hrAngle = (Double(hour % 12) + Double(minute) / 60.0) * (.pi / 6) - .pi * 0.5
            let minAngle = (Double(minute) + Double(second) / 60.0) * (.pi / 30) - .pi * 0.5
            let secAngle = Double(second) * (.pi / 30) - .pi * 0.5

            func drawHand(angle: Double, length: CGFloat, width: CGFloat, color: Color) {
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            drawHand(angle: hrAngle, length: r * 0.52, width: 4.5, color: tint)
            drawHand(angle: minAngle, length: r * 0.76, width: 3.0, color: tint.opacity(0.88))
            drawHand(angle: secAngle, length: r * 0.82, width: 1.4, color: MochyTheme.defaultAccent)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(tint))
        }
    }
}

/// 1:1 Mochy `BedsideTilesPlayerStyle`:
/// Adaptive two-tile split layout (landscape horizontal tiles, portrait stacked tiles) for desk/standby use.
public struct BedsideTilesPlayerView: View {
    @Bindable public var coordinator: AppCoordinator

    public var body: some View {
        let tint: Color = coordinator.settings.bedsideNightTint
            ? Color(red: 1.0, green: 0.68, blue: 0.30)
            : .white
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent

        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: timeline.date)
                let clockText = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)

                ZStack {
                    Color.black.ignoresSafeArea()

                    let layout = isLandscape ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
                    layout {
                        // Tile 1: Giant Clock & Active Lyric
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(timeline.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(tint.opacity(0.65))
                                Spacer()
                                if let rem = coordinator.player.sleepTimerRemainingSeconds {
                                    Label("\(rem / 60)m", systemImage: "moon.zzz.fill")
                                        .font(.caption2.bold())
                                        .foregroundStyle(tint)
                                }
                            }

                            Spacer()

                            Text(clockText)
                                .font(.system(size: isLandscape ? 78 : 88, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                                .minimumScaleFactor(0.6)

                            let liveLyric = coordinator.activeLyricLineText()
                            if !liveLyric.isEmpty {
                                Text(liveLyric)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(tint.opacity(0.82))
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        )

                        // Tile 2: Now Playing Cover + Controls
                        VStack(spacing: 16) {
                            Spacer()
                            ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 18)
                                .frame(width: isLandscape ? 130 : 156, height: isLandscape ? 130 : 156)
                                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

                            VStack(spacing: 3) {
                                Text(coordinator.player.currentItem?.title ?? "Not Playing")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(coordinator.player.currentItem?.artist ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(1)
                            }

                            MochySeekbarView(coordinator: coordinator, accentColor: accent)
                                .padding(.horizontal, 12)

                            TurntablePills(coordinator: coordinator)
                            Spacer()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            LinearGradient(colors: [accent.opacity(0.24), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 92)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 20))
                }
            }
        }
        .onAppear {
            #if os(iOS) && canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS) && canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }
}
