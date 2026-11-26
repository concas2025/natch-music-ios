import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import MochyAudio
import MochyCore
import MochyLyrics
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum ShareCardAspect: String, CaseIterable, Identifiable {
    case square = "1:1"
    case portrait = "4:5"
    case story = "9:16"

    public var id: String { rawValue }
    public var cgSize: CGSize {
        switch self {
        case .square: return CGSize(width: 340, height: 340)
        case .portrait: return CGSize(width: 320, height: 400)
        case .story: return CGSize(width: 280, height: 498)
        }
    }
}

public enum ShareBackdropPreset: String, CaseIterable, Identifiable {
    case ambient = "Ambient"
    case noir = "Pure Noir"
    case editorial = "Editorial"
    case frosted = "Frosted"
    public var id: String { rawValue }
}

/// 1:1 Mochy Share Studio:
/// - Aspect Ratios (`1:1`, `4:5`, `9:16`), 4 backdrop presets, multi-line synced lyric selector
/// - Native `ShareLink` sharing rendered high-res PNG image
/// - Real MP4 Karaoke Video Export (`AVAssetWriter` H.264 + cached/local audio composition muxing) -> `ShareLink`
public struct SongShareStudioView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var aspect: ShareCardAspect = .portrait
    @State private var backdrop: ShareBackdropPreset = .ambient
    @State private var selectedLineIndices: Set<Int> = [0, 1]
    @State private var includeRomanized = false
    @State private var includeTranslated = false
    @State private var exportedImageURL: URL?
    @State private var exportedVideoURL: URL?
    @State private var isExportingVideo = false
    @State private var exportStatus: String?

    public var body: some View {
        let item = coordinator.player.currentItem
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent
        let c1 = coordinator.paletteColors.indices.contains(1) ? coordinator.paletteColors[1] : Color(white: 0.14)

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // Live Preview Card
                    shareCardPreview(item: item, accent: accent, c1: c1)
                        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)

                    // Aspect & Backdrop Controls
                    Picker("Aspect Ratio", selection: $aspect) {
                        ForEach(ShareCardAspect.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ShareBackdropPreset.allCases) { preset in
                                Button(preset.rawValue) {
                                    backdrop = preset
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(backdrop == preset ? accent : MochyTheme.cardSurface)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    // Lyric Line Selector (up to 4 lines)
                    if let lines = coordinator.currentLyrics?.lines, !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Select Lyrics (up to 4 lines)").font(.subheadline.bold())
                                Spacer()
                                Toggle("Rom", isOn: $includeRomanized).labelsHidden()
                                Text("Rom").font(.caption2).foregroundStyle(.secondary)
                                Toggle("Tr", isOn: $includeTranslated).labelsHidden()
                                Text("Tr").font(.caption2).foregroundStyle(.secondary)
                            }

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(lines.prefix(40).enumerated()), id: \.offset) { idx, line in
                                        let picked = selectedLineIndices.contains(idx)
                                        Button {
                                            if picked {
                                                selectedLineIndices.remove(idx)
                                            } else if selectedLineIndices.count < 4 {
                                                selectedLineIndices.insert(idx)
                                            }
                                        } label: {
                                            HStack {
                                                Text(line.text)
                                                    .font(.caption)
                                                    .foregroundStyle(picked ? .white : .white.opacity(0.65))
                                                    .lineLimit(1)
                                                Spacer()
                                                if picked {
                                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(picked ? accent.opacity(0.22) : MochyTheme.cardSurface)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                    }

                    // Native Share Actions (PNG Card + MP4 Karaoke Video)
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                renderPNGCard(item: item, accent: accent, c1: c1)
                            } label: {
                                Label("Prepare PNG Card", systemImage: "photo.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)

                            if let exportedImageURL {
                                ShareLink(item: exportedImageURL) {
                                    Label("Share PNG", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await exportKaraokeMP4(item: item, accent: accent, c1: c1) }
                            } label: {
                                if isExportingVideo {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Label("Render Karaoke MP4", systemImage: "film.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isExportingVideo)

                            if let exportedVideoURL {
                                ShareLink(item: exportedVideoURL) {
                                    Label("Share MP4", systemImage: "video.badge.checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }

                        if let exportStatus {
                            Text(exportStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("Share Card & Video Studio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func selectedLines() -> [LyricsLine] {
        guard let lines = coordinator.currentLyrics?.lines, !lines.isEmpty else { return [] }
        let chosen = selectedLineIndices.sorted().compactMap { lines.indices.contains($0) ? lines[$0] : nil }
        return chosen.isEmpty ? Array(lines.prefix(2)) : chosen
    }

    private func shareCardPreview(item: PlaybackItem?, accent: Color, c1: Color) -> some View {
        let size = aspect.cgSize
        let chosen = selectedLines()

        return ZStack(alignment: .bottomLeading) {
            cardBackground(accent: accent, c1: c1)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: item?.thumbnailURL, cornerRadius: 10)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item?.title ?? "Natch Music")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item?.artist ?? "Hi-Res Audio")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 8) {
                    if chosen.isEmpty {
                        Text(item?.title ?? "Listening on Natch Music")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                    } else {
                        ForEach(chosen) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.text)
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(.white)
                                if includeRomanized, let rom = line.romanized, !rom.isEmpty {
                                    Text(rom).font(.caption2).foregroundStyle(.white.opacity(0.75))
                                }
                                if includeTranslated, let tr = line.translated, !tr.isEmpty {
                                    Text(tr).font(.caption2.italic()).foregroundStyle(accent)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                HStack {
                    Text("NATCH MUSIC")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    if !coordinator.player.activeQualityBadge.isEmpty {
                        Text(coordinator.player.activeQualityBadge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(22)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cardBackground(accent: Color, c1: Color) -> some View {
        switch backdrop {
        case .ambient:
            LinearGradient(colors: [accent.opacity(0.85), c1.opacity(0.72), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .noir:
            LinearGradient(colors: [Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom)
        case .editorial:
            LinearGradient(colors: [accent, Color(red: 0.10, green: 0.08, blue: 0.16)], startPoint: .topTrailing, endPoint: .bottomLeading)
        case .frosted:
            ZStack {
                LinearGradient(colors: [c1, accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Color.black.opacity(0.45)
            }
        }
    }

    @MainActor
    private func renderPNGCard(item: PlaybackItem?, accent: Color, c1: Color) {
        let renderer = ImageRenderer(content: shareCardPreview(item: item, accent: accent, c1: c1))
        renderer.scale = 3.0
        guard let cgImage = renderer.cgImage else {
            exportStatus = "Could not render card image."
            return
        }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("natch_share_card.png")
        if let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, nil)
            if CGImageDestinationFinalize(dest) {
                exportedImageURL = outURL
                exportStatus = "PNG card ready to share."
                return
            }
        }
        exportStatus = "Failed writing PNG card."
    }

    /// Renders a real H.264 `.mp4` Karaoke clip via `AVAssetWriter` and muxes the track's audio when cached/local.
    private func exportKaraokeMP4(item: PlaybackItem?, accent: Color, c1: Color) async {
        isExportingVideo = true
        exportStatus = "Rendering H.264 karaoke video..."
        defer { isExportingVideo = false }

        let width = 720
        let height = aspect == .square ? 720 : (aspect == .portrait ? 900 : 1280)
        let fps: Int32 = 30
        let chosen = selectedLines()
        let clipDurationSec: Double = 6.0
        let totalFrames = Int(clipDurationSec * Double(fps))

        let videoOnlyURL = FileManager.default.temporaryDirectory.appendingPathComponent("natch_karaoke_raw_\(UUID().uuidString.prefix(6)).mp4")
        let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("natch_karaoke_share.mp4")
        try? FileManager.default.removeItem(at: videoOnlyURL)
        try? FileManager.default.removeItem(at: finalURL)

        do {
            let writer = try AVAssetWriter(outputURL: videoOnlyURL, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false

            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
            guard writer.canAdd(input) else {
                exportStatus = "AVAssetWriter cannot add video input."
                return
            }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            let lyricStrings = chosen.isEmpty ? [item?.title ?? "Natch Music"] : chosen.map(\.text)
            let titleStr = item?.title ?? "Natch Music"
            let artistStr = item?.artist ?? ""

            for frameIdx in 0..<totalFrames {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                let progress = Double(frameIdx) / Double(max(1, totalFrames - 1))
                if let pb = renderKaraokePixelBuffer(
                    width: width,
                    height: height,
                    title: titleStr,
                    artist: artistStr,
                    lines: lyricStrings,
                    progress: progress
                ) {
                    let pts = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
                    adaptor.append(pb, withPresentationTime: pts)
                }
            }

            input.markAsFinished()
            await writer.finishWriting()

            // Mux audio clip if local or cached file is available
            if let audioURL = await coordinator.player.localAudioFileURLForCurrentTrack() {
                let comp = AVMutableComposition()
                let vAsset = AVURLAsset(url: videoOnlyURL)
                let aAsset = AVURLAsset(url: audioURL)
                let startAudioSec = chosen.first.map { max(0, Double($0.startMs) / 1000.0) } ?? coordinator.player.currentTime
                let clipRange = CMTimeRange(
                    start: CMTime(seconds: startAudioSec, preferredTimescale: 600),
                    duration: CMTime(seconds: clipDurationSec, preferredTimescale: 600)
                )

                if let vTrack = try? await vAsset.loadTracks(withMediaType: .video).first,
                   let compV = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compV.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: clipDurationSec, preferredTimescale: 600)),
                        of: vTrack,
                        at: .zero
                    )
                }
                if let aTrack = try? await aAsset.loadTracks(withMediaType: .audio).first,
                   let compA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compA.insertTimeRange(clipRange, of: aTrack, at: .zero)
                }

                if let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) {
                    exporter.outputURL = finalURL
                    exporter.outputFileType = .mp4
                    await exporter.export()
                    if exporter.status == .completed {
                        try? FileManager.default.removeItem(at: videoOnlyURL)
                        exportedVideoURL = finalURL
                        exportStatus = "Karaoke MP4 with audio ready to share!"
                        return
                    }
                }
            }

            try FileManager.default.moveItem(at: videoOnlyURL, to: finalURL)
            exportedVideoURL = finalURL
            exportStatus = "Karaoke MP4 ready to share!"
        } catch {
            exportStatus = "Video export failed: \(error.localizedDescription)"
        }
    }

    private func renderKaraokePixelBuffer(
        width: Int,
        height: Int,
        title: String,
        artist: String,
        lines: [String],
        progress: Double
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // Animated gradient backdrop
        let shift = CGFloat(sin(progress * .pi * 2) * 0.14)
        let colors = [
            CGColor(red: 0.45 + shift, green: 0.14, blue: 0.34, alpha: 1.0),
            CGColor(red: 0.08, green: 0.06, blue: 0.14, alpha: 1.0),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: CGFloat(height)),
                end: CGPoint(x: CGFloat(width), y: 0),
                options: []
            )
        }

        // Animated progress ribbon along bottom
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
        ctx.fill(CGRect(x: 54, y: 66, width: CGFloat(width - 108), height: 6))
        ctx.setFillColor(CGColor(red: 0.91, green: 0.27, blue: 0.44, alpha: 1.0))
        ctx.fill(CGRect(x: 54, y: 66, width: CGFloat(width - 108) * CGFloat(progress), height: 6))

        #if os(iOS) && canImport(UIKit)
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let artistAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: UIColor(white: 0.78, alpha: 1),
        ]
        (title as NSString).draw(in: CGRect(x: 54, y: 74, width: CGFloat(width - 108), height: 42), withAttributes: titleAttrs)
        (artist as NSString).draw(in: CGRect(x: 54, y: 118, width: CGFloat(width - 108), height: 32), withAttributes: artistAttrs)

        let activeLineIdx = min(lines.count - 1, Int(progress * Double(lines.count)))
        var yCursor: CGFloat = CGFloat(height) * 0.34
        for (idx, lineText) in lines.enumerated() {
            let isLit = idx <= activeLineIdx
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .heavy),
                .foregroundColor: isLit ? UIColor.white : UIColor(white: 1, alpha: 0.34),
            ]
            (lineText as NSString).draw(
                in: CGRect(x: 54, y: yCursor, width: CGFloat(width - 108), height: 110),
                withAttributes: attrs
            )
            yCursor += 116
        }

        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .heavy),
            .foregroundColor: UIColor(white: 1, alpha: 0.55),
        ]
        ("NATCH MUSIC" as NSString).draw(in: CGRect(x: 54, y: CGFloat(height - 110), width: 260, height: 26), withAttributes: brandAttrs)
        UIGraphicsPopContext()
        #endif

        return pb
    }
}
