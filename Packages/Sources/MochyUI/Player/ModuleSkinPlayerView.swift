import MochyAudio
import MochyCore
import MochyModules
import SwiftUI

/// Renders declarative `ModuleSkinManifest` blocks (`cover`, `title`, `artist`, `lyrics`, `visualizer`, `seekbar`, `transport`)
/// honoring `backgroundHex`, `accentHex`, block `height`/`cornerRadius`/`alignment`, and whitelisted `sanitizedLookOverrides`.
public struct ModuleSkinPlayerView: View {
    @Bindable public var coordinator: AppCoordinator
    public let onOpenQueue: () -> Void
    public let onOpenLyrics: () -> Void

    private static let builtInSkins: [ModuleSkinManifest] = [
        .defaultSkin,
        ModuleSkinManifest(
            id: "mochy.neon.mono",
            name: "Neon Mono",
            author: "Natch Studio",
            backgroundHex: ["#050608", "#0E1019"],
            accentHex: "#38BDF8",
            lookOverrides: ["pureBlack": "true"],
            blocks: [
                .init(id: "m1", kind: "title", height: nil, cornerRadius: nil, alignment: "leading"),
                .init(id: "m2", kind: "artist", height: nil, cornerRadius: nil, alignment: "leading"),
                .init(id: "m3", kind: "cover", height: 270, cornerRadius: 24, alignment: "center"),
                .init(id: "m4", kind: "lyrics", height: 64, cornerRadius: 14, alignment: "center"),
                .init(id: "m5", kind: "visualizer", height: 42, cornerRadius: 8, alignment: "center"),
                .init(id: "m6", kind: "seekbar", height: 44, cornerRadius: nil, alignment: "center"),
                .init(id: "m7", kind: "transport", height: 74, cornerRadius: nil, alignment: "center"),
            ]
        ),
        ModuleSkinManifest(
            id: "mochy.amber.tape",
            name: "Amber Tape",
            author: "Natch Studio",
            backgroundHex: ["#1A120B", "#080604"],
            accentHex: "#F59E0B",
            lookOverrides: ["blurQuality": "LOW"],
            blocks: [
                .init(id: "a1", kind: "cover", height: 240, cornerRadius: 12, alignment: "center"),
                .init(id: "a2", kind: "visualizer", height: 52, cornerRadius: 10, alignment: "center"),
                .init(id: "a3", kind: "title", height: nil, cornerRadius: nil, alignment: "center"),
                .init(id: "a4", kind: "artist", height: nil, cornerRadius: nil, alignment: "center"),
                .init(id: "a5", kind: "seekbar", height: 42, cornerRadius: nil, alignment: "center"),
                .init(id: "a6", kind: "transport", height: 72, cornerRadius: nil, alignment: "center"),
            ]
        ),
    ]

    public var body: some View {
        let skin = coordinator.currentModuleSkin
        let overrides = skin.sanitizedLookOverrides
        let bgColors = skin.backgroundHex.compactMap { MochyTheme.colorFromHex($0) }
        let accent = MochyTheme.colorFromHex(overrides[.accentColor] ?? skin.accentHex)
            ?? coordinator.paletteColors.first
            ?? MochyTheme.defaultAccent

        ZStack {
            LinearGradient(
                colors: bgColors.isEmpty ? [Color(white: 0.08), .black] : bgColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Spacer(minLength: 84)

                    // Quick skin switcher chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.builtInSkins, id: \.id) { preset in
                                let active = preset.id == skin.id
                                Button(preset.name) {
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                        coordinator.currentModuleSkin = preset
                                    }
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(active ? accent : Color.white.opacity(0.10))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    ForEach(skin.blocks) { block in
                        renderBlock(block, accent: accent)
                    }

                    if let author = skin.author {
                        Text("Skin: \(skin.name) · by \(author)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.42))
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: ModuleSkinManifest.Block, accent: Color) -> some View {
        let item = coordinator.player.currentItem
        let align = horizontalAlignment(for: block.alignment)

        switch block.kind.lowercased() {
        case "cover":
            let h = CGFloat(block.height ?? 280)
            let radius = block.cornerRadius ?? coordinator.settings.thumbnailCornerRadius
            HStack {
                if align == .trailing { Spacer() }
                ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: radius)
                    .frame(width: h, height: h)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                if align == .leading { Spacer() }
            }

        case "title":
            HStack {
                if align == .trailing { Spacer() }
                VStack(alignment: align, spacing: 2) {
                    Text(item?.title ?? "Not Playing")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !coordinator.currentModuleSkin.blocks.contains(where: { $0.kind.lowercased() == "artist" }) {
                        Text(item?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                if align == .leading { Spacer() }
            }

        case "artist":
            HStack {
                if align == .trailing { Spacer() }
                Text(item?.artist ?? "")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                if align == .leading { Spacer() }
            }

        case "lyrics":
            let live = coordinator.activeLyricLineText()
            Button(action: onOpenLyrics) {
                Text(live.isEmpty ? "Tap to open Lyrics Stage" : live)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(live.isEmpty ? 0.55 : 0.95))
                    .multilineTextAlignment(align == .leading ? .leading : (align == .trailing ? .trailing : .center))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(block.height ?? 56))
                    .padding(.horizontal, 12)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.cornerRadius ?? 14), style: .continuous))
            }
            .buttonStyle(.plain)

        case "visualizer":
            let h = CGFloat(block.height ?? 46)
            let bins = coordinator.player.spectrumBins
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, val in
                    Capsule()
                        .fill(accent.opacity(0.45 + Double(val) * 0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, h * CGFloat(min(1, max(0, val)))))
                }
            }
            .frame(height: h, alignment: .bottom)
            .padding(.horizontal, 8)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.cornerRadius ?? 10), style: .continuous))

        case "seekbar":
            MochySeekbarView(coordinator: coordinator, accentColor: accent)

        case "transport":
            TransportControlsRow(coordinator: coordinator, onOpenQueue: onOpenQueue)

        default:
            EmptyView()
        }
    }

    private func horizontalAlignment(for raw: String?) -> HorizontalAlignment {
        switch raw?.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        default: return .center
        }
    }
}
