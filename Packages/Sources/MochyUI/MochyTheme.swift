import CoreGraphics
import Foundation
import ImageIO
import MochyCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum MochyTheme {
    public static let defaultAccent = Color(red: 0.91, green: 0.27, blue: 0.44)
    public static let cardSurface = Color(white: 0.08)
    public static let elevatedSurface = Color(white: 0.14)
    public static let subtleBorder = Color.white.opacity(0.10)

    public static func background(pureBlack: Bool) -> Color {
        pureBlack ? .black : Color(red: 0.05, green: 0.05, blue: 0.07)
    }

    public static func colorFromHex(_ hex: String?) -> Color? {
        guard var clean = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

/// Downsamples artwork to 24x24 CGImage and extracts 4 vibrant dynamic colors (Mochy `PlayerColorExtractor`).
public enum ArtworkPaletteExtractor {
    public static func extractColors(fromImageData data: Data) -> [Color] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return [MochyTheme.defaultAccent, .indigo, .purple, .black]
        }

        let size = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return [MochyTheme.defaultAccent, .indigo, .purple, .black]
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var buckets: [(r: Double, g: Double, b: Double, score: Double)] = []
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[idx]) / 255.0
            let g = Double(pixels[idx + 1]) / 255.0
            let b = Double(pixels[idx + 2]) / 255.0
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard luma > 0.08 && luma < 0.90 else { continue }
            buckets.append((r, g, b, sat * 2.2 + luma * 0.4))
        }

        let top = buckets.sorted { $0.score > $1.score }
        guard !top.isEmpty else { return [MochyTheme.defaultAccent, .indigo, .purple, .black] }
        let strideStep = max(1, top.count / 4)
        return (0..<4).map { i in
            let p = top[min(i * strideStep, top.count - 1)]
            return Color(red: p.r, green: p.g, blue: p.b)
        }
    }
}

/// 30Hz throttled orbital ambient backdrop powered by `App/Shaders/MochyShaders.metal`
/// (`mochyAmbientBlob` + `mochyFilmGrain`) on iOS high-quality mode, with smooth SwiftUI fallback.
public struct AmbientBackdropView: View {
    public let colors: [Color]
    public let style: FlagshipBackground
    public let blurQuality: BlurQuality
    public let isPaused: Bool

    public init(colors: [Color], style: FlagshipBackground, blurQuality: BlurQuality = .high, isPaused: Bool = false) {
        self.colors = colors
        self.style = style
        self.blurQuality = blurQuality
        self.isPaused = isPaused
    }

    public var body: some View {
        let c0 = colors.indices.contains(0) ? colors[0] : MochyTheme.defaultAccent
        let c1 = colors.indices.contains(1) ? colors[1] : .indigo
        let c2 = colors.indices.contains(2) ? colors[2] : .purple
        let c3 = colors.indices.contains(3) ? colors[3] : .teal

        Group {
            switch style {
            case .solid:
                c0.opacity(0.45).overlay(Color.black.opacity(0.62))
            case .darkGradient:
                LinearGradient(colors: [c0.opacity(0.55), .black, .black], startPoint: .top, endPoint: .bottom)
            case .coverGradient:
                LinearGradient(colors: [c0.opacity(0.85), c1.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .appleMusic, .ambient:
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { timeline in
                    let t = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
                    GeometryReader { geo in
                        #if os(iOS)
                        if blurQuality == .high {
                            Rectangle()
                                .fill(.black)
                                .colorEffect(
                                    ShaderLibrary.default.mochyAmbientBlob(
                                        .float2(geo.size),
                                        .float(t),
                                        .color(c0),
                                        .color(c1),
                                        .color(c2),
                                        .color(c3)
                                    )
                                )
                                .colorEffect(
                                    ShaderLibrary.default.mochyFilmGrain(
                                        .float(0.032),
                                        .float(t)
                                    )
                                )
                                .overlay(Color.black.opacity(0.24))
                        } else {
                            fallbackOrbs(c0: c0, c1: c1, c2: c2, c3: c3, t: Double(t), size: geo.size)
                        }
                        #else
                        fallbackOrbs(c0: c0, c1: c1, c2: c2, c3: c3, t: Double(t), size: geo.size)
                        #endif
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func fallbackOrbs(c0: Color, c1: Color, c2: Color, c3: Color, t: Double, size: CGSize) -> some View {
        ZStack {
            Color.black
            orb(c0, geo: size, x: 0.25 + 0.22 * sin(t * 0.4), y: 0.28 + 0.18 * cos(t * 0.3), scale: 0.85)
            orb(c1, geo: size, x: 0.72 + 0.20 * cos(t * 0.32), y: 0.38 + 0.20 * sin(t * 0.36), scale: 0.9)
            orb(c2, geo: size, x: 0.35 + 0.24 * sin(t * 0.27 + 1.2), y: 0.75 + 0.15 * cos(t * 0.25), scale: 0.95)
            orb(c3, geo: size, x: 0.70 + 0.18 * cos(t * 0.38 + 2.0), y: 0.72 + 0.18 * sin(t * 0.29), scale: 0.75)
        }
        .blur(radius: blurQuality == .high ? 60 : 34)
        .overlay(Color.black.opacity(0.32))
    }

    private func orb(_ color: Color, geo: CGSize, x: Double, y: Double, scale: Double) -> some View {
        Circle()
            .fill(color.opacity(0.75))
            .frame(width: max(geo.width, 200) * scale, height: max(geo.width, 200) * scale)
            .position(x: geo.width * x, y: geo.height * y)
    }
}

public struct ArtworkImageView: View {
    public let urlString: String?
    public let cornerRadius: Double

    public init(urlString: String?, cornerRadius: Double = 14) {
        self.urlString = urlString
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                if url.isFileURL {
                    localFileImage(url: url)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFill()
                        default:
                            placeholder
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func localFileImage(url: URL) -> some View {
        #if os(iOS) && canImport(UIKit)
        if let data = try? Data(contentsOf: url), let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg).resizable().scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
