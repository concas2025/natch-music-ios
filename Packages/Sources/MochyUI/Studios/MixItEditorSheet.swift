import AVFoundation
import MochyAudio
import MochyCore
import MochyDatabase
import SwiftUI

/// Dual-Track DJ MixIt Transition Editor:
/// - Extracts real PCM amplitude waveforms when track audio is local/cached (with deterministic fallback)
/// - Lets user configure any of the 19 `CrossmixStyle`s, overlap duration, cue timestamps, Beat Snap, Bass Swap, and 6 stem levels
/// - Persists directly to GRDB `playlist_transition` table (read live by `MochyAudioPlayer.evaluateCrossmixTrigger`)
public struct MixItEditorSheet: View {
    @Bindable public var coordinator: AppCoordinator
    public let playlistId: String
    public let fromSong: SongEntity
    public let toSong: SongEntity

    @Environment(\.dismiss) private var dismiss

    @State private var selectedStyle: CrossmixStyle = .bassSwap
    @State private var durationSeconds: Double = 6.0
    @State private var outStartSeconds: Double = 0
    @State private var inStartSeconds: Double = 0
    @State private var snapToBeat: Bool = true
    @State private var bassSwap: Bool = true
    @State private var outVoiceLevel: Double = 1.0
    @State private var outBassLevel: Double = 1.0
    @State private var outInstrumentLevel: Double = 1.0
    @State private var inVoiceLevel: Double = 1.0
    @State private var inBassLevel: Double = 1.0
    @State private var inInstrumentLevel: Double = 1.0

    @State private var outWaveform: [Float] = []
    @State private var inWaveform: [Float] = []

    public init(coordinator: AppCoordinator, playlistId: String, fromSong: SongEntity, toSong: SongEntity) {
        self.coordinator = coordinator
        self.playlistId = playlistId
        self.fromSong = fromSong
        self.toSong = toSong
    }

    public var body: some View {
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent
        let fromMax = Double(max(30, fromSong.duration > 0 ? fromSong.duration : 180))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Dual Track Header + Real Waveforms
                    VStack(spacing: 12) {
                        waveformTrackCard(
                            label: "OUTGOING",
                            title: fromSong.title,
                            bars: outWaveform,
                            color: accent,
                            cueRatio: outStartSeconds / max(1, fromMax)
                        )
                        waveformTrackCard(
                            label: "INCOMING",
                            title: toSong.title,
                            bars: inWaveform,
                            color: .cyan,
                            cueRatio: inStartSeconds / Double(max(30, toSong.duration > 0 ? toSong.duration : 180))
                        )
                    }

                    // All 19 DJ Styles Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DJ Transition Style (19 Styles)").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CrossmixStyle.allCases, id: \.self) { style in
                                    let active = selectedStyle == style
                                    Button(style.rawValue) {
                                        selectedStyle = style
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(active ? accent : MochyTheme.cardSurface)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Timing & Beat Controls
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timing & Alignment").font(.headline)
                        sliderRow("Overlap", value: $durationSeconds, range: 1.5...14.0, unit: "s")
                        sliderRow("Out Cue", value: $outStartSeconds, range: 0...max(10, fromMax - 2), unit: "s")
                        sliderRow("In Cue", value: $inStartSeconds, range: 0...30, unit: "s")
                        Toggle("Beat Snap Alignment", isOn: $snapToBeat)
                        Toggle("Bass Swap Crossover", isOn: $bassSwap)
                    }
                    .padding(14)
                    .background(MochyTheme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // 6 Stem Mix Sliders
                    VStack(alignment: .leading, spacing: 10) {
                        Text("6-Stem Transition Levels").font(.headline)
                        sliderRow("Out Voice", value: $outVoiceLevel, range: 0...1, unit: "%", scale: 100)
                        sliderRow("Out Bass", value: $outBassLevel, range: 0...1, unit: "%", scale: 100)
                        sliderRow("Out Inst.", value: $outInstrumentLevel, range: 0...1, unit: "%", scale: 100)
                        Divider()
                        sliderRow("In Voice", value: $inVoiceLevel, range: 0...1, unit: "%", scale: 100)
                        sliderRow("In Bass", value: $inBassLevel, range: 0...1, unit: "%", scale: 100)
                        sliderRow("In Inst.", value: $inInstrumentLevel, range: 0...1, unit: "%", scale: 100)
                    }
                    .padding(14)
                    .background(MochyTheme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        saveTransition()
                        coordinator.settings.crossmixMode = .mixit
                        coordinator.playLocalSong(fromSong, allSongs: [fromSong, toSong], playlistId: playlistId)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            coordinator.player.seek(to: max(0, outStartSeconds - 1.5))
                        }
                    } label: {
                        Label("Save & Preview Live Transition", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("MixIt DJ Editor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransition()
                        dismiss()
                    }
                }
            }
            .task {
                loadInitialState()
                outWaveform = await extractWaveform(for: fromSong)
                inWaveform = await extractWaveform(for: toSong)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadInitialState() {
        let fromDur = Double(max(30, fromSong.duration > 0 ? fromSong.duration : 180))
        outStartSeconds = max(0, fromDur - 8.0)

        let existing = (try? coordinator.database.fetchTransitions(playlistId: playlistId))?
            .first { $0.fromSongId == fromSong.id && $0.toSongId == toSong.id }
        if let tr = existing {
            if let raw = tr.outEffect, let style = CrossmixStyle(rawValue: raw) {
                selectedStyle = style
            }
            durationSeconds = max(1.5, Double(tr.durationMs) / 1000.0)
            outStartSeconds = Double(tr.outStartMs) / 1000.0
            inStartSeconds = Double(tr.inStartMs) / 1000.0
            snapToBeat = tr.snapToBeat ?? true
            bassSwap = tr.bassSwap ?? true
            outVoiceLevel = tr.outVoiceLevel
            outBassLevel = tr.outBassLevel
            outInstrumentLevel = tr.outInstrumentLevel
            inVoiceLevel = tr.inVoiceLevel
            inBassLevel = tr.inBassLevel
            inInstrumentLevel = tr.inInstrumentLevel
        }
    }

    private func saveTransition() {
        let tr = PlaylistTransition(
            playlistId: playlistId,
            fromSongId: fromSong.id,
            toSongId: toSong.id,
            outStartMs: Int64(outStartSeconds * 1000),
            inStartMs: Int64(inStartSeconds * 1000),
            durationMs: Int64(durationSeconds * 1000),
            outEffect: selectedStyle.rawValue,
            inEffect: selectedStyle.rawValue,
            snapToBeat: snapToBeat,
            bassSwap: bassSwap,
            presetName: selectedStyle.rawValue,
            outVoiceLevel: outVoiceLevel,
            outBassLevel: outBassLevel,
            outInstrumentLevel: outInstrumentLevel,
            inVoiceLevel: inVoiceLevel,
            inBassLevel: inBassLevel,
            inInstrumentLevel: inInstrumentLevel
        )
        try? coordinator.database.upsertTransition(tr)
    }

    private func waveformTrackCard(label: String, title: String, bars: [Float], color: Color, cueRatio: Double) -> some View {
        let displayBars = bars.isEmpty ? Array(repeating: Float(0.35), count: 44) : bars
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.caption2.bold()).foregroundStyle(color)
                Text(title).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(displayBars.enumerated()), id: \.offset) { _, mag in
                            Capsule()
                                .fill(color.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(4, geo.size.height * CGFloat(min(1, max(0.1, mag)))))
                        }
                    }
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2, height: geo.size.height)
                        .offset(x: geo.size.width * CGFloat(min(1, max(0, cueRatio))))
                }
            }
            .frame(height: 44)
        }
        .padding(12)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, scale: Double = 1.0) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.85)).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue * scale).rounded()))\(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// Reads real PCM amplitude envelope from cached/local audio file; falls back to deterministic fingerprint if remote.
    private func extractWaveform(for song: SongEntity, bins: Int = 44) async -> [Float] {
        var fileURL = PlaybackItem.resolveLocalURI(song.localUri)
        if fileURL == nil, await coordinator.player.chunkCache.isFullyCached(mediaId: song.id) {
            fileURL = await coordinator.player.chunkCache.completeFileURL(mediaId: song.id)
        }
        if let fileURL, let audioFile = try? AVAudioFile(forReading: fileURL), audioFile.length > 0 {
            let totalFrames = Int(audioFile.length)
            let framesPerBin = max(1, totalFrames / bins)
            let sampleChunk = min(framesPerBin, 2048)
            var peaks: [Float] = []
            if let buf = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(sampleChunk)) {
                for b in 0..<bins {
                    audioFile.framePosition = AVAudioFramePosition(min(totalFrames - 1, b * framesPerBin))
                    if (try? audioFile.read(into: buf, frameCount: AVAudioFrameCount(sampleChunk))) != nil,
                       let ch = buf.floatChannelData?[0] {
                        var sum: Float = 0
                        let n = Int(buf.frameLength)
                        for i in 0..<n { sum += abs(ch[i]) }
                        peaks.append(n > 0 ? min(1.0, (sum / Float(n)) * 3.2) : 0.15)
                    } else {
                        peaks.append(0.15)
                    }
                }
                return peaks
            }
        }
        // Deterministic fallback for uncached remote streams
        let seed = abs(song.id.hashValue)
        return (0..<bins).map { idx in
            let wave = abs(sin(Double(idx + seed % 17) * 0.42) * cos(Double(idx) * 0.19))
            return Float(0.22 + wave * 0.72)
        }
    }
}
