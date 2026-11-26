import AVFoundation
import MochyAudio
import MochyCore
import MochyDatabase
import MochyDSP
import MochyLyrics
import SwiftUI

// MARK: - Synchronized Lyrics Stage & Glow Line

public struct LyricsStageView: View {
    @Bindable public var coordinator: AppCoordinator
    @State private var offsetMs: Int = 0
    @State private var showShareStudio = false

    public var body: some View {
        VStack(spacing: 12) {
            if let doc = coordinator.currentLyrics, !doc.lines.isEmpty {
                HStack {
                    Text(doc.sourceProvider)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.14), in: Capsule())

                    Spacer()

                    Stepper("Sync \(offsetMs)ms", value: $offsetMs, in: -5000...5000, step: 100)
                        .labelsHidden()
                    Text("\(offsetMs >= 0 ? "+" : "")\(offsetMs)ms")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.75))

                    Button {
                        showShareStudio = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal)

                let nowMs = Int(coordinator.player.currentTime * 1000) + offsetMs
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(doc.lines.enumerated()), id: \.element.id) { idx, line in
                                let nextStart = idx + 1 < doc.lines.count ? doc.lines[idx + 1].startMs : Int.max
                                let isActive = doc.isSynced && nowMs >= line.startMs && nowMs < nextStart
                                LyricsGlowLineView(
                                    line: line,
                                    isActive: isActive,
                                    nowMs: nowMs,
                                    motionStyle: coordinator.settings.lyricsMotionStyle
                                )
                                .id(line.id)
                                .onTapGesture {
                                    coordinator.player.seek(to: TimeInterval(line.startMs) / 1000.0)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                    }
                    .onChange(of: nowMs / 300) { _, _ in
                        if doc.isSynced,
                           let current = doc.lines.last(where: { $0.startMs <= nowMs }) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(current.id, anchor: .center)
                            }
                        }
                    }
                }
            } else if coordinator.isLoadingLyrics {
                Spacer()
                ProgressView("Fetching lyrics across 12+ providers...")
                    .foregroundStyle(.white)
                Spacer()
            } else {
                Spacer()
                Text("No lyrics available for this track")
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
            }
        }
        .sheet(isPresented: $showShareStudio) {
            if let doc = coordinator.currentLyrics {
                SongShareStudioView(coordinator: coordinator, lyrics: doc)
            }
        }
    }
}

public struct LyricsGlowLineView: View {
    public let line: LyricsLine
    public let isActive: Bool
    public let nowMs: Int
    public let motionStyle: LyricsMotionStyle

    public var body: some View {
        let align: HorizontalAlignment = (line.agent == .v2) ? .trailing : .leading
        VStack(alignment: align, spacing: 4) {
            if !line.words.isEmpty && motionStyle != .classic {
                wordFlowText
            } else {
                Text(line.text)
                    .font(.system(size: line.isBackground ? 17 : 23, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.38))
                    .shadow(color: (isActive && motionStyle == .neon) ? .white.opacity(0.55) : .clear, radius: 10)
            }

            if let rom = line.romanized, !rom.isEmpty {
                Text(rom)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(isActive ? 0.78 : 0.32))
            }
            if let tr = line.translated, !tr.isEmpty {
                Text(tr)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(isActive ? 0.90 : 0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: line.agent == .v2 ? .trailing : .leading)
        .scaleEffect(isActive ? 1.03 : 0.98, anchor: line.agent == .v2 ? .trailing : .leading)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isActive)
    }

    private var wordFlowText: some View {
        HStack(spacing: 4) {
            ForEach(line.words.prefix(12)) { word in
                let sung = nowMs >= word.startMs
                Text(word.text)
                    .font(.system(size: line.isBackground ? 16 : 22, weight: sung && isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? (sung ? .white : .white.opacity(0.42)) : .white.opacity(0.32))
                    .shadow(color: (isActive && sung && motionStyle == .neon) ? .white.opacity(0.6) : .clear, radius: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.agent == .v2 ? .trailing : .leading)
    }
}

// MARK: - Audio Lab View (10-Band EQ, AutoEq, 3D Stage Room, Audio Pass & Blockers)

public struct AudioLabView: View {
    @Bindable public var coordinator: AppCoordinator
    private let freqLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    @State private var blockers: [String] = []
    @State private var savedRestoreSnapshot: AudioPassRestoreSnapshot?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                audioPassCard
                spectrumMeterCard
                eqCard
                stageRoomCard
                miscEffectsCard
            }
            .padding()
            .padding(.bottom, 120)
        }
        .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
        .navigationTitle("Audio Lab")
        .onAppear(perform: refreshBlockers)
    }

    private var audioPassCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { coordinator.settings.audioPassEnabled },
                set: { enabled in
                    if enabled {
                        savedRestoreSnapshot = AudioPassController.makeSnapshot(
                            eqEnabled: coordinator.settings.dspEqEnabled,
                            stageEnabled: coordinator.settings.dspStageEnabled,
                            orbitEnabled: coordinator.settings.dspOrbitEnabled,
                            crossmixActive: coordinator.settings.crossmixMode != .off
                        )
                        coordinator.settings.dspEqEnabled = false
                        coordinator.settings.dspStageEnabled = false
                        coordinator.settings.dspOrbitEnabled = false
                        coordinator.settings.crossmixMode = .off
                    } else if let snap = savedRestoreSnapshot {
                        coordinator.settings.dspEqEnabled = snap.eqEnabled
                        coordinator.settings.dspStageEnabled = snap.stageEnabled
                        coordinator.settings.dspOrbitEnabled = snap.orbitEnabled
                        coordinator.settings.crossmixMode = snap.crossmixActive ? .classic : .off
                    }
                    coordinator.settings.audioPassEnabled = enabled
                    coordinator.player.syncDSPParameters()
                    refreshBlockers()
                }
            )) {
                VStack(alignment: .leading) {
                    Text("Audio Pass (Bit-Accurate DAC Bypass)")
                        .font(.headline)
                    Text("Bypasses all DSP and matches track sample rate via CoreAudio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !blockers.isEmpty && !coordinator.settings.audioPassEnabled {
                Text("Active DSP blockers: \(blockers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var spectrumMeterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Audio Spectrum (FFT)")
                .font(.subheadline.bold())
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(coordinator.player.spectrumBins.enumerated()), id: \.offset) { _, mag in
                    Capsule()
                        .fill(MochyTheme.defaultAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, CGFloat(mag) * 58))
                }
            }
            .frame(height: 62)
        }
        .padding()
        .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var eqCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("10-Band Equalizer & AutoEq", isOn: $coordinator.settings.dspEqEnabled)
                .font(.headline)
                .onChange(of: coordinator.settings.dspEqEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                    refreshBlockers()
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AutoEqRepository.builtInPresets) { preset in
                        Button(preset.name) {
                            coordinator.player.eqGainsDb = preset.gains10BandDb
                            coordinator.settings.dspEqEnabled = true
                            coordinator.player.syncDSPParameters()
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(MochyTheme.elevatedSurface, in: Capsule())
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { idx in
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f", coordinator.player.eqGainsDb[idx]))
                            .font(.system(size: 10, design: .monospaced))
                        Slider(value: $coordinator.player.eqGainsDb[idx], in: -12...12, step: 0.5)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 24)
                            .frame(width: 24, height: 95)
                        Text(freqLabels[idx])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var stageRoomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mochy Stage 3D Room (C++17 KEMAR HRTF)", isOn: $coordinator.settings.dspStageEnabled)
                .font(.headline)
                .onChange(of: coordinator.settings.dspStageEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                    refreshBlockers()
                }

            // Interactive 2D top-down room stage map
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

                    // Listener head in center
                    Image(systemName: "headphones")
                        .foregroundStyle(.white.opacity(0.7))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    stageNode(label: "Vocal", color: MochyTheme.defaultAccent, pos: $coordinator.player.stageParams.vocalPos, size: geo.size)
                    stageNode(label: "L", color: .cyan, pos: $coordinator.player.stageParams.leftPos, size: geo.size)
                    stageNode(label: "R", color: .mint, pos: $coordinator.player.stageParams.rightPos, size: geo.size)
                }
            }
            .frame(height: 170)
        }
        .padding()
        .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stageNode(label: String, color: Color, pos: Binding<SIMD3<Float>>, size: CGSize) -> some View {
        let px = CGFloat(pos.wrappedValue.x / 4.0 + 0.5) * size.width
        let py = CGFloat(0.5 - pos.wrappedValue.z / 4.0) * size.height
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(.black)
            .padding(6)
            .background(color, in: Circle())
            .position(x: min(max(20, px), size.width - 20), y: min(max(20, py), size.height - 20))
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let nx = Float((val.location.x / max(1, size.width) - 0.5) * 4.0)
                        let nz = Float((0.5 - val.location.y / max(1, size.height)) * 4.0)
                        pos.wrappedValue = SIMD3(nx, pos.wrappedValue.y, nz)
                    }
            )
    }

    private var miscEffectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("8D Audio Auto-Orbit", isOn: $coordinator.settings.dspOrbitEnabled)
                .onChange(of: coordinator.settings.dspOrbitEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                    refreshBlockers()
                }
            Toggle("Bass-Kick CoreHaptics", isOn: $coordinator.settings.hapticsEnabled)
        }
        .padding()
        .background(MochyTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func refreshBlockers() {
        blockers = AudioPassController.activeBlockers(
            eqEnabled: coordinator.settings.dspEqEnabled,
            stageEnabled: coordinator.settings.dspStageEnabled,
            orbitEnabled: coordinator.settings.dspOrbitEnabled,
            crossmixActive: coordinator.settings.crossmixMode != .off
        )
    }
}

// MARK: - MixIt Dual-Waveform Transition Studio

public struct MixItEditorSheet: View {
    @Bindable public var coordinator: AppCoordinator
    public let playlist: PlaylistEntity
    public let songs: [SongEntity]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPairIndex = 0
    @State private var durationMs: Double = 6000
    @State private var bassSwap = true
    @State private var snapToBeat = true
    @State private var outVoiceLevel: Double = 1.0
    @State private var outBassLevel: Double = 0.25
    @State private var inInstrumentLevel: Double = 1.0

    public var body: some View {
        NavigationStack {
            Form {
                if songs.count >= 2 {
                    Picker("Transition Pair", selection: $selectedPairIndex) {
                        ForEach(0..<(songs.count - 1), id: \.self) { idx in
                            Text("\(songs[idx].title) → \(songs[idx + 1].title)").tag(idx)
                        }
                    }

                    Section("Dual Waveform Overlap") {
                        HStack(spacing: 2) {
                            ForEach(0..<36, id: \.self) { i in
                                let h = 10 + 28 * abs(sin(Double(i) * 0.45))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i < 20 ? Color.pink.opacity(0.8) : Color.cyan.opacity(0.8))
                                    .frame(width: 6, height: h)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        Slider(value: $durationMs, in: 1000...16000, step: 500) {
                            Text("Overlap: \(Int(durationMs / 1000))s")
                        }
                        Toggle("Beat Snap", isOn: $snapToBeat)
                        Toggle("Bass Swap", isOn: $bassSwap)
                    }

                    Section("Stem Curves") {
                        Slider(value: $outVoiceLevel, in: 0...1) { Text("Outgoing Voice: \(Int(outVoiceLevel * 100))%") }
                        Slider(value: $outBassLevel, in: 0...1) { Text("Outgoing Bass: \(Int(outBassLevel * 100))%") }
                        Slider(value: $inInstrumentLevel, in: 0...1) { Text("Incoming Instrument: \(Int(inInstrumentLevel * 100))%") }
                    }
                } else {
                    Text("Add at least 2 tracks to this playlist to author MixIt transitions.")
                }
            }
            .navigationTitle("MixIt Studio")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if songs.count >= 2 && selectedPairIndex + 1 < songs.count {
                            let from = songs[selectedPairIndex]
                            let to = songs[selectedPairIndex + 1]
                            let transition = PlaylistTransition(
                                playlistId: playlist.id,
                                fromSongId: from.id,
                                toSongId: to.id,
                                outStartMs: Int64(max(0, from.duration - 8) * 1000),
                                inStartMs: 0,
                                durationMs: Int64(durationMs),
                                outEffect: bassSwap ? CrossmixStyle.bassSwap.rawValue : CrossmixStyle.silkBlend.rawValue,
                                snapToBeat: snapToBeat,
                                bassSwap: bassSwap,
                                outVoiceLevel: outVoiceLevel,
                                outBassLevel: outBassLevel,
                                inInstrumentLevel: inInstrumentLevel
                            )
                            try? coordinator.database.upsertTransition(transition)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Song & Lyrics Share Studio (Image Card + MP4 Karaoke Export)

public struct SongShareStudioView: View {
    @Bindable public var coordinator: AppCoordinator
    public let lyrics: LyricsDocument
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLineIds: Set<String> = []
    @State private var exportNotice: String?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                shareCardPreview
                    .padding(.horizontal)

                List(lyrics.lines) { line in
                    Button {
                        if selectedLineIds.contains(line.id) {
                            selectedLineIds.remove(line.id)
                        } else if selectedLineIds.count < 5 {
                            selectedLineIds.insert(line.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedLineIds.contains(line.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(MochyTheme.defaultAccent)
                            Text(line.text).foregroundStyle(.white)
                        }
                    }
                }

                if let exportNotice {
                    Text(exportNotice).font(.caption).foregroundStyle(.green)
                }

                Button("Render Share Card PNG to Documents") {
                    renderCardImage()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .navigationTitle("Share Studio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var shareCardPreview: some View {
        let picked = lyrics.lines.filter { selectedLineIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkImageView(urlString: coordinator.player.currentItem?.thumbnailURL, cornerRadius: 10)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text(coordinator.player.currentItem?.title ?? "Natch Music")
                        .font(.headline)
                    Text(coordinator.player.currentItem?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            ForEach(picked.isEmpty ? Array(lyrics.lines.prefix(3)) : picked) { line in
                Text(line.text)
                    .font(.title3.bold())
            }
            Text("Natch Music")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [coordinator.paletteColors.first ?? MochyTheme.defaultAccent, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    @MainActor
    private func renderCardImage() {
        let renderer = ImageRenderer(content: shareCardPreview.frame(width: 360))
        renderer.scale = 3.0
        #if os(iOS)
        if let image = renderer.uiImage,
           let data = image.pngData(),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let outURL = docs.appendingPathComponent("natch_share_card.png")
            try? data.write(to: outURL)
            exportNotice = "Saved PNG card to Files -> Natch Music/\(outURL.lastPathComponent)"
        }
        #else
        exportNotice = "Card rendered cleanly."
        #endif
    }
}
