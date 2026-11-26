import MochyCore
import MochyDatabase
import SwiftUI
#if os(iOS) && canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum IdCardFinish: String, CaseIterable, Sendable {
    case dark = "Obsidian Dark"
    case silver = "Brushed Silver"
}

// MARK: - Profile ID Card Front (1:1 Mochy 1.89:1 Card + 90° Vertical MarqueeStrip)

public struct ProfileIdCardFront: View {
    public let username: String
    public let cardNumber: String
    public let joinedDate: Date
    public let avatarURL: URL?
    public let finish: IdCardFinish
    public var onTapAvatar: (() -> Void)?

    public init(
        username: String,
        cardNumber: String,
        joinedDate: Date,
        avatarURL: URL?,
        finish: IdCardFinish = .dark,
        onTapAvatar: (() -> Void)? = nil
    ) {
        self.username = username
        self.cardNumber = cardNumber
        self.joinedDate = joinedDate
        self.avatarURL = avatarURL
        self.finish = finish
        self.onTapAvatar = onTapAvatar
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let u = max(0.5, w / 332.0) // Exact Mochy unit scaling: 332dp reference width
            let isSilver = finish == .silver
            let fgPrimary: Color = isSilver ? Color(white: 0.10) : .white
            let fgSecondary: Color = isSilver ? Color(white: 0.30) : .white.opacity(0.62)

            ZStack {
                // Card Base Material
                if isSilver {
                    brushedSilverSurface
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.185, green: 0.185, blue: 0.195), Color(red: 0.11, green: 0.11, blue: 0.125)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // Subtle diagonal specular sheen
                LinearGradient(
                    colors: [.clear, .white.opacity(isSilver ? 0.34 : 0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(spacing: 0) {
                    // Left Main Content Area
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("USR#\(cardNumber)")
                                .font(.system(size: 10.5 * u, weight: .bold, design: .monospaced))
                                .foregroundStyle(fgSecondary)
                            Spacer()
                            Text("NATCH PASS")
                                .font(.system(size: 9 * u, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(isSilver ? Color(white: 0.25) : MochyTheme.defaultAccent)
                        }
                        .padding(.bottom, 12 * u)

                        HStack(alignment: .center, spacing: 14 * u) {
                            // 96u Circular Avatar
                            avatarCircle(size: 92 * u, isSilver: isSilver)
                                .onTapGesture { onTapAvatar?() }

                            VStack(alignment: .leading, spacing: 4 * u) {
                                Text("ID CARD OF")
                                    .font(.system(size: 9.5 * u, weight: .bold))
                                    .tracking(1.6)
                                    .foregroundStyle(fgSecondary)

                                Text(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Listener" : username)
                                    .font(.system(size: 21 * u, weight: .black, design: .rounded))
                                    .foregroundStyle(fgPrimary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)

                                Text("Joined \(joinedDate.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.system(size: 10.5 * u, weight: .semibold))
                                    .foregroundStyle(fgSecondary)
                                    .padding(.top, 2 * u)
                            }
                            Spacer(minLength: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 18 * u)
                    .padding(.trailing, 10 * u)
                    .padding(.vertical, 16 * u)

                    // Right 40u Vertical 90°-Rotated Downward Scrolling MarqueeStrip
                    VerticalMarqueeStrip(
                        text: "NATCH MUSIC  •  MOCHY AUDIO LAB  •  HI-RES FLAC  •  ",
                        width: 40 * u,
                        isSilver: isSilver
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20 * u, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                    .strokeBorder(isSilver ? Color.white.opacity(0.65) : Color.white.opacity(0.16), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .aspectRatio(1.89, contentMode: .fit)
    }

    private var brushedSilverSurface: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(white: 0.86), location: 0.0),
                    .init(color: Color(white: 0.96), location: 0.28),
                    .init(color: Color(white: 0.75), location: 0.54),
                    .init(color: Color(white: 0.91), location: 0.82),
                    .init(color: Color(white: 0.78), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Horizontal brushed aluminum grain lines
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    let alpha = (Int(y) % 3 == 0) ? 0.08 : 0.03
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.8)), with: .color(.black.opacity(alpha)))
                    y += 2.2
                }
            }
        }
    }

    @ViewBuilder
    private func avatarCircle(size: CGFloat, isSilver: Bool) -> some View {
        ZStack {
            if let avatarURL {
                ArtworkImageView(urlString: avatarURL.absoluteString, cornerRadius: size * 0.5)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
        .overlay(
            Circle()
                .strokeBorder(isSilver ? Color.black.opacity(0.25) : Color.white.opacity(0.28), lineWidth: 2)
        )
    }
}

private struct VerticalMarqueeStrip: View {
    let text: String
    let width: CGFloat
    let isSilver: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let cycle = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8.0) / 8.0)
            let stripHeight: CGFloat = 220

            ZStack {
                (isSilver ? Color.black.opacity(0.10) : Color.black.opacity(0.32))
                GeometryReader { geo in
                    let repeated = text + text + text
                    Text(repeated)
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(isSilver ? Color(white: 0.16) : Color.white.opacity(0.75))
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .position(x: geo.size.width * 0.5, y: (cycle * stripHeight) - stripHeight * 0.25)
                }
                .clipped()
            }
            .frame(width: width)
        }
    }
}

// MARK: - Profile ID Card Back (Real Code 128 Barcode + Interactive Scratch-Off Silver Foil + Green Laser -> Recap)

public struct ProfileIdCardBack: View {
    public let codeString: String
    public let finish: IdCardFinish
    public let onUnlockedRecap: () -> Void

    @State private var scratchPoints: [CGPoint] = []
    @State private var hitCells: Set<Int> = []
    @State private var isRevealed = false
    @State private var laserProgress: CGFloat = 0
    @State private var showVerifiedStamp = false
    @State private var flakes: [ScratchFlake] = []

    private let gridCols = 14
    private let gridRows = 4

    private struct ScratchFlake: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let createdAt: TimeInterval
    }

    public init(codeString: String, finish: IdCardFinish = .dark, onUnlockedRecap: @escaping () -> Void) {
        self.codeString = codeString
        self.finish = finish
        self.onUnlockedRecap = onUnlockedRecap
    }

    public var body: some View {
        let modules = Code128Encoder.encode(codeString)
        let isSilver = finish == .silver

        GeometryReader { geo in
            let w = geo.size.width
            let u = max(0.5, w / 332.0)

            ZStack {
                RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                    .fill(
                        isSilver
                            ? LinearGradient(colors: [Color(white: 0.88), Color(white: 0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(white: 0.14), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                VStack(spacing: 10 * u) {
                    HStack {
                        Text(isRevealed ? "RECAP PASS VERIFIED" : "SCRATCH SILVER FOIL TO SCAN RECAP")
                            .font(.system(size: 9.5 * u, weight: .heavy, design: .monospaced))
                            .foregroundStyle(isSilver ? Color(white: 0.25) : .white.opacity(0.68))
                        Spacer()
                        if isRevealed {
                            Button("Open Recap") { onUnlockedRecap() }
                                .font(.system(size: 9.5 * u, weight: .bold))
                                .foregroundStyle(Color(red: 0.32, green: 1.0, blue: 0.48))
                        }
                    }

                    // Barcode Strip + Interactive Silver Scratch Coating + Green Laser
                    GeometryReader { stripGeo in
                        let sw = stripGeo.size.width
                        let sh = stripGeo.size.height

                        ZStack {
                            // Layer 1: Real scannable Code 128 vector bars
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white)
                                .overlay {
                                    Canvas { ctx, size in
                                        guard !modules.isEmpty else { return }
                                        let padX: CGFloat = 14
                                        let padY: CGFloat = 10
                                        let barW = (size.width - padX * 2) / CGFloat(modules.count)
                                        let barH = size.height - padY * 2
                                        for (idx, isDark) in modules.enumerated() where isDark {
                                            let rect = CGRect(x: padX + CGFloat(idx) * barW, y: padY, width: max(1, barW + 0.15), height: barH)
                                            ctx.fill(Path(rect), with: .color(.black))
                                        }
                                    }
                                }

                            // Layer 2: Silver Scratch-Off Foil erased by finger strokes (`destinationOut` in `compositingGroup`)
                            if !isRevealed {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(white: 0.72), Color(white: 0.88), Color(white: 0.68), Color(white: 0.82)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    Text("SCRATCH HERE")
                                        .font(.system(size: 13 * u, weight: .black, design: .monospaced))
                                        .tracking(2.2)
                                        .foregroundStyle(.black.opacity(0.32))

                                    // Erase path
                                    Canvas { ctx, _ in
                                        for pt in scratchPoints {
                                            let brush = CGRect(x: pt.x - 18, y: pt.y - 18, width: 36, height: 36)
                                            ctx.fill(Path(ellipseIn: brush), with: .color(.black))
                                        }
                                    }
                                    .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { val in
                                            recordScratch(at: val.location, size: CGSize(width: sw, height: sh))
                                        }
                                )
                            }

                            // Layer 3: Falling silver scratch flakes
                            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: flakes.isEmpty)) { tl in
                                let now = tl.date.timeIntervalSinceReferenceDate
                                Canvas { ctx, _ in
                                    for flake in flakes {
                                        let age = now - flake.createdAt
                                        guard age < 0.7 else { continue }
                                        let dropY = flake.y + CGFloat(age * age) * 180
                                        let alpha = max(0, 1.0 - age / 0.7)
                                        let r = CGRect(x: flake.x, y: dropY, width: flake.size, height: flake.size * 0.7)
                                        ctx.fill(Path(r), with: .color(Color(white: 0.84).opacity(alpha)))
                                    }
                                }
                                .allowsHitTesting(false)
                            }

                            // Layer 4: Green Laser Scanner Sweep (`#52FF7A`)
                            if isRevealed && laserProgress > 0 && laserProgress < 1.0 {
                                Rectangle()
                                    .fill(Color(red: 0.32, green: 1.0, blue: 0.48))
                                    .frame(width: 3, height: sh)
                                    .shadow(color: Color(red: 0.32, green: 1.0, blue: 0.48), radius: 8)
                                    .position(x: sw * laserProgress, y: sh * 0.5)
                            }

                            // Layer 5: Angled VERIFIED Neon Stamp
                            if showVerifiedStamp {
                                Text("VERIFIED")
                                    .font(.system(size: 16 * u, weight: .black, design: .monospaced))
                                    .tracking(2.5)
                                    .foregroundStyle(Color(red: 0.32, green: 1.0, blue: 0.48))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color(red: 0.32, green: 1.0, blue: 0.48), lineWidth: 2)
                                    )
                                    .rotationEffect(.degrees(-12))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .frame(height: 86 * u)

                    Text(codeString)
                        .font(.system(size: 12 * u, weight: .bold, design: .monospaced))
                        .tracking(3.2)
                        .foregroundStyle(isSilver ? Color(white: 0.20) : .white.opacity(0.84))
                }
                .padding(18 * u)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20 * u, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                    .strokeBorder(isSilver ? Color.white.opacity(0.65) : Color.white.opacity(0.16), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .aspectRatio(1.89, contentMode: .fit)
    }

    private func recordScratch(at point: CGPoint, size: CGSize) {
        guard !isRevealed else { return }
        scratchPoints.append(point)
        if scratchPoints.count > 260 { scratchPoints.removeFirst(40) }

        let now = Date().timeIntervalSinceReferenceDate
        flakes.append(ScratchFlake(x: point.x + CGFloat.random(in: -8...8), y: point.y, size: CGFloat.random(in: 3...6), createdAt: now))
        flakes.removeAll { now - $0.createdAt > 0.75 }

        let col = max(0, min(gridCols - 1, Int((point.x / max(1, size.width)) * CGFloat(gridCols))))
        let row = max(0, min(gridRows - 1, Int((point.y / max(1, size.height)) * CGFloat(gridRows))))
        let cellId = row * gridCols + col
        if hitCells.insert(cellId).inserted {
            #if os(iOS) && canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            #endif
        }

        let ratio = Double(hitCells.count) / Double(gridCols * gridRows)
        if ratio >= 0.42 {
            triggerRevealSequence()
        }
    }

    private func triggerRevealSequence() {
        withAnimation(.easeOut(duration: 0.35)) {
            isRevealed = true
        }
        #if os(iOS) && canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        laserProgress = 0.02
        withAnimation(.easeInOut(duration: 0.72)) {
            laserProgress = 0.99
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                showVerifiedStamp = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            onUnlockedRecap()
        }
    }
}

// MARK: - Profile & Listening Stats Screen (Hosts Flippable ID Card + Recap Story Launcher)

public struct ProfileAndRecapScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var isFlipped = false
    @State private var cardFinish: IdCardFinish = .dark
    @State private var showRecapStory = false
    @State private var showEditProfile = false
    @State private var draftUsername = ""
    @State private var topSongs: [SongEntity] = []
    @State private var topArtists: [(artist: ArtistEntity, playTimeMs: Int64)] = []
    @State private var totalMinutes: Int = 0
    #if os(iOS) && canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let cal = Calendar.current
        let now = Date()
        let codeStr = String(format: "MFY%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 3D Flippable Profile ID Card
                    ZStack {
                        ProfileIdCardFront(
                            username: coordinator.settings.profileUsername,
                            cardNumber: coordinator.settings.profileCardNumber,
                            joinedDate: Date(timeIntervalSince1970: coordinator.settings.profileJoinedTimestamp),
                            avatarURL: coordinator.profileAvatarURL(),
                            finish: cardFinish
                        )
                        .opacity(isFlipped ? 0 : 1)

                        ProfileIdCardBack(
                            codeString: codeStr,
                            finish: cardFinish,
                            onUnlockedRecap: { showRecapStory = true }
                        )
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .opacity(isFlipped ? 1 : 0)
                    }
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .animation(.spring(response: 0.55, dampingFraction: 0.80), value: isFlipped)

                    // Card Controls Row
                    HStack(spacing: 10) {
                        Button {
                            withAnimation { isFlipped.toggle() }
                        } label: {
                            Label(isFlipped ? "Flip to Front" : "Flip & Scratch Barcode", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MochyTheme.buttonFill)

                        Button {
                            cardFinish = (cardFinish == .dark) ? .silver : .dark
                        } label: {
                            Label(cardFinish == .dark ? "Silver" : "Dark", systemImage: "sparkles")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)

                        Button {
                            draftUsername = coordinator.settings.profileUsername
                            showEditProfile = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Recap Launch Banner
                    Button {
                        showRecapStory = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Natch Listening Recap")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                                Text("\(totalMinutes) minutes listened · \(topSongs.count) top tracks")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.76))
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundStyle(MochyTheme.defaultAccent)
                        }
                        .padding(16)
                        .background(
                            LinearGradient(colors: [Color(white: 0.14), MochyTheme.cardSurface], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Top Artists Section
                    if !topArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Artists").font(.headline)
                            ForEach(Array(topArtists.prefix(5).enumerated()), id: \.offset) { idx, entry in
                                HStack {
                                    Text("#\(idx + 1)")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(MochyTheme.defaultAccent)
                                        .frame(width: 28, alignment: .leading)
                                    Text(entry.artist.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(max(1, Int(entry.playTimeMs / 60_000)))m")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(MochyTheme.cardSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    // Top Songs Section
                    if !topSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Most Played Tracks").font(.headline)
                            ForEach(Array(topSongs.prefix(10).enumerated()), id: \.offset) { idx, song in
                                Button {
                                    coordinator.playLocalSong(song, allSongs: topSongs)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text("\(idx + 1)")
                                            .font(.caption.bold().monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                        ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                                            .frame(width: 42, height: 42)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                            Text("\(max(1, Int(song.totalPlayTime / 60_000))) min played")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(MochyTheme.cardSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("ID Card & Stats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadStats() }
            .sheet(isPresented: $showEditProfile) {
                editProfileSheet
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showRecapStory) {
                RecapStoryView(coordinator: coordinator)
            }
            #else
            .sheet(isPresented: $showRecapStory) {
                RecapStoryView(coordinator: coordinator)
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private var editProfileSheet: some View {
        NavigationStack {
            Form {
                Section("Display Name on ID Card") {
                    TextField("Your name", text: $draftUsername)
                }
                #if os(iOS) && canImport(PhotosUI)
                Section("Profile Avatar") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Photo from Library", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                coordinator.saveProfileAvatar(data: data)
                            }
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Edit ID Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditProfile = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.settings.profileUsername = draftUsername
                        showEditProfile = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadStats() {
        topSongs = (try? coordinator.database.fetchTopSongs(limit: 15)) ?? []
        topArtists = (try? coordinator.database.fetchTopArtists(limit: 10)) ?? []
        let ms = (try? coordinator.database.fetchTotalPlayTimeMs()) ?? 0
        totalMinutes = Int(ms / 60_000)
    }
}
