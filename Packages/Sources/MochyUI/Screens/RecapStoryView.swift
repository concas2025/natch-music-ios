import ImageIO
import MochyCore
import MochyDatabase
import SwiftUI
import UniformTypeIdentifiers

/// Full-screen interactive Mochy Recap Story powered by live GRDB listening telemetry:
/// 1. Welcome Slide  2. Total Minutes  3. Favorite Weekday 7-Bar Chart  4. Top Artists  5. Top Songs  6. Printable Music Receipt + ShareLink
public struct RecapStoryView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var pageIndex = 0
    @State private var totalPlayMs: Int64 = 0
    @State private var weekdayMs: [Int64] = Array(repeating: 0, count: 7)
    @State private var topArtists: [(artist: ArtistEntity, playTimeMs: Int64)] = []
    @State private var topSongs: [SongEntity] = []
    @State private var receiptShareURL: URL?

    private let totalPages = 6
    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent

        ZStack(alignment: .top) {
            storyBackground(page: pageIndex, accent: accent)
                .ignoresSafeArea()

            // Tap left / right invisible navigation zones (under top chrome)
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            pageIndex = max(0, pageIndex - 1)
                        }
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if pageIndex + 1 < totalPages {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                pageIndex += 1
                            }
                        } else {
                            dismiss()
                        }
                    }
            }
            .ignoresSafeArea()

            VStack(spacing: 14) {
                // Top Story Progress Bars + Close Button
                HStack(spacing: 5) {
                    ForEach(0..<totalPages, id: \.self) { idx in
                        Capsule()
                            .fill(idx <= pageIndex ? Color.white : Color.white.opacity(0.28))
                            .frame(height: 3.5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)

                HStack {
                    Text("NATCH RECAP")
                        .font(.caption.weight(.black))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 18)

                Spacer()

                slideContent(page: pageIndex, accent: accent)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .id(pageIndex)

                Spacer()

                Text("Tap left or right to navigate · \(pageIndex + 1)/\(totalPages)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadTelemetry()
        }
    }

    @ViewBuilder
    private func slideContent(page: Int, accent: Color) -> some View {
        switch page {
        case 0:
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(accent)
                Text("Welcome back,\n\(coordinator.settings.profileUsername.isEmpty ? "Listener" : coordinator.settings.profileUsername)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("Your real listening fingerprint from local history & plays.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                if let topSong = topSongs.first {
                    Button {
                        coordinator.playLocalSong(topSong, allSongs: topSongs)
                    } label: {
                        Label("Play #1 Track: \(topSong.title)", systemImage: "play.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 8)
                }
            }

        case 1:
            let totalMinutes = Int(totalPlayMs / 60_000)
            let hours = Double(totalMinutes) / 60.0
            VStack(spacing: 12) {
                Text("TOTAL TIME IN THE ZONE")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(totalMinutes)")
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("minutes (\(String(format: "%.1f", hours)) hours)")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                Text("Across \(coordinator.librarySongs.count) library tracks and \(coordinator.libraryPlaylists.count) playlists.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }

        case 2:
            let maxVal = max(1, weekdayMs.max() ?? 1)
            let bestDayIdx = weekdayMs.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            VStack(spacing: 18) {
                Text("YOUR PEAK LISTENING DAY")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(dayNames[bestDayIdx])
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<7, id: \.self) { idx in
                        let frac = CGFloat(weekdayMs[idx]) / CGFloat(maxVal)
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(idx == bestDayIdx ? accent : Color.white.opacity(0.32))
                                .frame(height: max(12, frac * 145))
                            Text(dayNames[idx])
                                .font(.caption2.bold())
                                .foregroundStyle(idx == bestDayIdx ? .white : .white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 175, alignment: .bottom)
                .padding(16)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

        case 3:
            VStack(alignment: .leading, spacing: 14) {
                Text("TOP ARTISTS")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                if topArtists.isEmpty {
                    Text("Keep playing tracks to unlock your top artists.")
                        .font(.headline).foregroundStyle(.white.opacity(0.75))
                } else {
                    ForEach(Array(topArtists.prefix(5).enumerated()), id: \.offset) { idx, entry in
                        HStack {
                            Text("#\(idx + 1)")
                                .font(.title3.weight(.black).monospacedDigit())
                                .foregroundStyle(accent)
                                .frame(width: 40, alignment: .leading)
                            Text(entry.artist.name)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(max(1, Int(entry.playTimeMs / 60_000)))m")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(12)
                        .background(.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

        case 4:
            VStack(alignment: .leading, spacing: 14) {
                Text("TOP SONGS")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                if topSongs.isEmpty {
                    Text("No play events recorded yet.")
                        .font(.headline).foregroundStyle(.white.opacity(0.75))
                } else {
                    ForEach(Array(topSongs.prefix(5).enumerated()), id: \.offset) { idx, song in
                        HStack(spacing: 12) {
                            Text("#\(idx + 1)")
                                .font(.headline.weight(.black).monospacedDigit())
                                .foregroundStyle(accent)
                                .frame(width: 32, alignment: .leading)
                            ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                Text("\(max(1, Int(song.totalPlayTime / 60_000))) min")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

        default:
            VStack(spacing: 14) {
                musicReceiptCard
                HStack(spacing: 12) {
                    Button("Render Receipt PNG") {
                        renderReceiptImage()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    if let receiptShareURL {
                        ShareLink(item: receiptShareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var musicReceiptCard: some View {
        let code = "USR\(coordinator.settings.profileCardNumber)"
        let modules = Code128Encoder.encode(code)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 2) {
                Text("NATCH MUSIC RECEIPT")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                Text("USR#\(coordinator.settings.profileCardNumber) · \(Date().formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .frame(maxWidth: .infinity)

            Divider().background(.black.opacity(0.3))

            ForEach(Array(topSongs.prefix(5).enumerated()), id: \.offset) { idx, song in
                HStack {
                    Text(String(format: "%02d %@", idx + 1, song.title))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text("\(max(1, Int(song.totalPlayTime / 60_000)))m")
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            Divider().background(.black.opacity(0.3))

            HStack {
                Text("TOTAL LISTENING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(Int(totalPlayMs / 60_000)) MIN")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
            }

            // Code 128 Barcode footer
            Canvas { ctx, size in
                guard !modules.isEmpty else { return }
                let barW = size.width / CGFloat(modules.count)
                for (i, dark) in modules.enumerated() where dark {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * barW, y: 0, width: max(1, barW), height: size.height)), with: .color(.black))
                }
            }
            .frame(height: 36)
            .padding(.top, 4)
        }
        .foregroundStyle(.black)
        .padding(18)
        .background(Color(red: 0.96, green: 0.95, blue: 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }

    private func storyBackground(page: Int, accent: Color) -> LinearGradient {
        let palettes: [[Color]] = [
            [accent.opacity(0.82), .black],
            [.indigo.opacity(0.85), .black],
            [.teal.opacity(0.75), .black],
            [.purple.opacity(0.80), .black],
            [MochyTheme.defaultAccent.opacity(0.75), Color(white: 0.06)],
            [Color(white: 0.14), .black],
        ]
        let colors = palettes[page % palettes.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func loadTelemetry() {
        totalPlayMs = (try? coordinator.database.fetchTotalPlayTimeMs()) ?? 0
        weekdayMs = (try? coordinator.database.fetchWeekdayPlayTimeMs()) ?? Array(repeating: 0, count: 7)
        topArtists = (try? coordinator.database.fetchTopArtists(limit: 5)) ?? []
        topSongs = (try? coordinator.database.fetchTopSongs(limit: 8)) ?? []
    }

    @MainActor
    private func renderReceiptImage() {
        let renderer = ImageRenderer(content: musicReceiptCard.frame(width: 320))
        renderer.scale = 3.0
        guard let cg = renderer.cgImage else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("natch_recap_receipt.png")
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            if CGImageDestinationFinalize(dest) {
                receiptShareURL = url
            }
        }
    }
}
