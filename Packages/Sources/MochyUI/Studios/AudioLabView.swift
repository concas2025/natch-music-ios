import MochyAudio
import MochyCore
import MochyDSP
import SwiftUI

/// Full 1:1 Mochy Audio Lab controlling live inline C++ `MochyFXEngine` & `MochyStageEngine` (KEMAR HRTF):
/// - Audio Pass bit-exact bypass with Blocker Guard & Restore Snapshot
/// - Live 32-band `Accelerate` `vDSP` FFT spectrum
/// - 10-Band EQ + AutoEq presets (applying both gains + preamp) + AutoEq text import sheet
/// - Preamp, Loudness Normalization (-14 LUFS), Bass/Treble Boost, Analog Warmth, Reverb, Playback Speed
/// - 3D Stage Room drag pad + live 6-band `stageLevels` meters + 8D Orbit + Bass-Kick Haptics + Crossmix
public struct AudioLabView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var audioPassRestore: AudioPassRestoreSnapshot?
    @State private var activeBlockersAlert: [String] = []
    @State private var showBlockersAlert = false
    @State private var showAutoEqImport = false
    @State private var autoEqInputText = ""
    @State private var autoEqStatus: String?

    private let eqLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private let stageBandLabels = ["Vocal", "Center", "Left", "Right", "Rear", "Sub"]

    public var body: some View {
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Live Real vDSP FFT Visualizer
                    spectrumCard(accent: accent)

                    // 2. Audio Pass (Bit-Exact Bypass Guard)
                    audioPassCard

                    // 3. 10-Band Equalizer & AutoEq
                    equalizerCard(accent: accent)

                    // 4. Tone, Dynamics & Playback Speed
                    toneAndDynamicsCard

                    // 5. 3D Stage Room (KEMAR HRTF) + Live 6-Band Meters
                    stageRoomCard(accent: accent)

                    // 6. 8D Orbit, Bass-Kick Haptics & DJ Crossmix
                    spatialAndCrossmixCard
                }
                .padding(16)
            }
            .background(.black)
            .navigationTitle("Audio Lab (C++ DSP)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disable DSP for Bit-Exact Audio Pass?", isPresented: $showBlockersAlert) {
                Button("Disable & Enable Audio Pass", role: .destructive) {
                    audioPassRestore = AudioPassController.makeSnapshot(
                        eqEnabled: coordinator.settings.dspEqEnabled,
                        stageEnabled: coordinator.settings.dspStageEnabled,
                        orbitEnabled: coordinator.settings.dspOrbitEnabled,
                        crossmixActive: coordinator.settings.crossmixMode != .off
                    )
                    coordinator.settings.dspEqEnabled = false
                    coordinator.settings.dspStageEnabled = false
                    coordinator.settings.dspOrbitEnabled = false
                    coordinator.settings.crossmixMode = .off
                    coordinator.settings.audioPassEnabled = true
                    coordinator.player.syncDSPParameters()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Audio Pass bypasses: \(activeBlockersAlert.joined(separator: ", ")). Settings will be restored when Audio Pass is turned off.")
            }
            .sheet(isPresented: $showAutoEqImport) {
                autoEqImportSheet
            }
        }
        .preferredColorScheme(.dark)
    }

    private func spectrumCard(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live 32-Band FFT (Accelerate vDSP)", systemImage: "waveform.path.ecg")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(coordinator.settings.audioPassEnabled ? "BYPASS" : "LIVE PCM")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(coordinator.settings.audioPassEnabled ? Color.green.opacity(0.25) : accent.opacity(0.25))
                    .foregroundStyle(coordinator.settings.audioPassEnabled ? .green : accent)
                    .clipShape(Capsule())
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(coordinator.player.spectrumBins.enumerated()), id: \.offset) { _, bin in
                    Capsule()
                        .fill(LinearGradient(colors: [accent, Color.white.opacity(0.85)], startPoint: .bottom, endPoint: .top))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, CGFloat(min(1, max(0, bin))) * 76))
                }
            }
            .frame(height: 78, alignment: .bottom)
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var audioPassCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { coordinator.settings.audioPassEnabled },
                set: { wantOn in
                    if wantOn {
                        let blockers = AudioPassController.activeBlockers(
                            eqEnabled: coordinator.settings.dspEqEnabled,
                            stageEnabled: coordinator.settings.dspStageEnabled,
                            orbitEnabled: coordinator.settings.dspOrbitEnabled,
                            crossmixActive: coordinator.settings.crossmixMode != .off
                        )
                        if blockers.isEmpty {
                            coordinator.settings.audioPassEnabled = true
                            coordinator.player.syncDSPParameters()
                        } else {
                            activeBlockersAlert = blockers
                            showBlockersAlert = true
                        }
                    } else {
                        coordinator.settings.audioPassEnabled = false
                        if let snap = audioPassRestore {
                            coordinator.settings.dspEqEnabled = snap.eqEnabled
                            coordinator.settings.dspStageEnabled = snap.stageEnabled
                            coordinator.settings.dspOrbitEnabled = snap.orbitEnabled
                            if snap.crossmixActive { coordinator.settings.crossmixMode = .classic }
                            audioPassRestore = nil
                        }
                        coordinator.player.syncDSPParameters()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Pass (Bit-Exact Mode)").font(.headline)
                    Text("Bypasses all biquads, limiter & spatializers and requests native DAC sample rate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func equalizerCard(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("10-Band Parametric EQ", isOn: $coordinator.settings.dspEqEnabled)
                    .font(.headline)
                    .disabled(coordinator.settings.audioPassEnabled)
                    .onChange(of: coordinator.settings.dspEqEnabled) { _, _ in
                        coordinator.player.syncDSPParameters()
                    }
            }

            // Built-in AutoEq Presets + Custom Import
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AutoEqRepository.builtInPresets) { preset in
                        Button(preset.name) {
                            coordinator.settings.dspEqEnabled = true
                            coordinator.player.eqGainsDb = preset.gains10BandDb
                            coordinator.player.preampDb = preset.preampDb
                            autoEqStatus = "Applied \(preset.name) (Preamp \(String(format: "%.1f", preset.preampDb)) dB)"
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .disabled(coordinator.settings.audioPassEnabled)
                    }

                    Button {
                        showAutoEqImport = true
                    } label: {
                        Label("Import AutoEq", systemImage: "doc.text.magnifyingglass")
                            .font(.caption2.bold())
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.24))
                            .foregroundStyle(accent)
                            .clipShape(Capsule())
                    }
                    .disabled(coordinator.settings.audioPassEnabled)
                }
            }

            if let autoEqStatus {
                Text(autoEqStatus).font(.caption2).foregroundStyle(accent)
            }

            // 10 Band Sliders
            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { idx in
                    VStack(spacing: 4) {
                        Text(String(format: "%+.0f", coordinator.player.eqGainsDb[idx]))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        VerticalSliderBar(
                            value: Binding(
                                get: { coordinator.player.eqGainsDb[idx] },
                                set: { newVal in
                                    coordinator.player.eqGainsDb[idx] = newVal
                                }
                            ),
                            range: -12...12,
                            accent: accent
                        )
                        .frame(height: 112)
                        .disabled(!coordinator.settings.dspEqEnabled || coordinator.settings.audioPassEnabled)
                        .opacity(coordinator.settings.dspEqEnabled && !coordinator.settings.audioPassEnabled ? 1 : 0.4)

                        Text(eqLabels[idx])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var toneAndDynamicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tone, Loudness & Speed").font(.headline)

            Toggle("Loudness Normalization (-14 LUFS)", isOn: $coordinator.settings.loudnessNormalizationEnabled)
                .font(.subheadline)
                .onChange(of: coordinator.settings.loudnessNormalizationEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                }

            dspSliderRow("Preamp", value: $coordinator.player.preampDb, range: -12...12, format: "%+.1f dB")
            dspSliderRow("Bass Boost", value: $coordinator.player.bassBoostDb, range: 0...12, format: "+%.1f dB")
            dspSliderRow("Treble Boost", value: $coordinator.player.trebleBoostDb, range: -6...12, format: "%+.1f dB")
            dspSliderRow("Analog Warmth", value: $coordinator.player.warmth, range: 0...1, format: "%.0f%%", multiplier: 100)
            dspSliderRow("Hall Reverb", value: $coordinator.player.reverbMix, range: 0...0.85, format: "%.0f%%", multiplier: 100)
            dspSliderRow("Playback Speed", value: $coordinator.player.playbackSpeed, range: 0.5...2.0, format: "%.2fx")
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(coordinator.settings.audioPassEnabled)
        .opacity(coordinator.settings.audioPassEnabled ? 0.5 : 1)
    }

    private func stageRoomCard(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("3D Stage Room (KEMAR HRTF)", isOn: $coordinator.settings.dspStageEnabled)
                .font(.headline)
                .disabled(coordinator.settings.audioPassEnabled)
                .onChange(of: coordinator.settings.dspStageEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                }

            if coordinator.settings.dspStageEnabled && !coordinator.settings.audioPassEnabled {
                Toggle("Headphones Binaural HRTF", isOn: $coordinator.player.stageParams.headphonesMode)
                    .font(.caption)

                // Interactive Top-Down 2D Room Pad for dragging Vocal placement
                GeometryReader { padGeo in
                    let w = padGeo.size.width
                    let h = padGeo.size.height
                    let vPos = coordinator.player.stageParams.vocalPos
                    let px = CGFloat((vPos.x + 3.0) / 6.0) * w
                    let py = CGFloat((3.0 - vPos.z) / 6.0) * h

                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.65))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                            )

                        // Center listener head icon
                        Image(systemName: "headphones")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.45))

                        // Draggable Vocal Node
                        Circle()
                            .fill(accent)
                            .frame(width: 30, height: 30)
                            .overlay(Text("V").font(.caption.bold()).foregroundStyle(.white))
                            .shadow(color: accent.opacity(0.6), radius: 8)
                            .position(x: max(18, min(w - 18, px)), y: max(18, min(h - 18, py)))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let nx = Float((val.location.x / max(1, w)) * 6.0 - 3.0)
                                let nz = Float(3.0 - (val.location.y / max(1, h)) * 6.0)
                                coordinator.player.stageParams.vocalPos = SIMD3(
                                    max(-3, min(3, nx)),
                                    0.3,
                                    max(-3, min(3, nz))
                                )
                            }
                    )
                }
                .frame(height: 150)

                dspSliderRow("Room Mix", value: $coordinator.player.stageParams.roomAmount, range: 0...1, format: "%.0f%%", multiplier: 100)
                dspSliderRow("Room Width", value: $coordinator.player.stageParams.roomWidthMeters, range: 3...14, format: "%.1f m")

                // Live 6-Band Stage Energy Meters fed directly from C++ `mochy_stage_levels`
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live 6-Stem Stage Activity").font(.caption2.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { idx in
                            let lv = coordinator.player.stageLevels.indices.contains(idx) ? coordinator.player.stageLevels[idx] : 0
                            VStack(spacing: 4) {
                                GeometryReader { g in
                                    ZStack(alignment: .bottom) {
                                        Capsule().fill(.white.opacity(0.10))
                                        Capsule()
                                            .fill(accent)
                                            .frame(height: max(3, g.size.height * CGFloat(min(1, max(0, lv * 2.5)))))
                                    }
                                }
                                .frame(height: 36)
                                Text(stageBandLabels[idx])
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var spatialAndCrossmixCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Motion, Haptics & DJ Crossmix").font(.headline)

            Toggle("8D Auto-Orbit Panning", isOn: $coordinator.settings.dspOrbitEnabled)
                .disabled(coordinator.settings.audioPassEnabled)
                .onChange(of: coordinator.settings.dspOrbitEnabled) { _, _ in
                    coordinator.player.syncDSPParameters()
                }

            Toggle("Bass-Kick CoreHaptics (Sub-Bass Pulse)", isOn: $coordinator.settings.hapticsEnabled)

            Picker("Crossmix Mode", selection: $coordinator.settings.crossmixMode) {
                Text("Off").tag(CrossmixMode.off)
                Text("Auto DJ (19 Styles)").tag(CrossmixMode.classic)
                Text("MixIt Custom").tag(CrossmixMode.mixit)
            }
            .pickerStyle(.segmented)
            .disabled(coordinator.settings.audioPassEnabled)

            if coordinator.settings.crossmixMode != .off {
                HStack {
                    Text("Overlap").font(.caption).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(coordinator.settings.crossmixDurationMs) / 1000.0 },
                            set: { coordinator.settings.crossmixDurationMs = Int($0 * 1000) }
                        ),
                        in: 2.0...12.0,
                        step: 0.5
                    )
                    Text(String(format: "%.1fs", Double(coordinator.settings.crossmixDurationMs) / 1000.0))
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dspSliderRow(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        format: String,
        multiplier: Float = 1.0
    ) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.85)).frame(width: 98, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * multiplier))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var autoEqImportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste ParametricEQ / AutoEq text (e.g. `Preamp: -4.2 dB` + `Filter 1: ON PK Fc 105 Hz Gain 3.4 dB`):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $autoEqInputText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(MochyTheme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Parse & Apply AutoEq") {
                    if let parsed = AutoEqRepository.parseAutoEqText(autoEqInputText) {
                        coordinator.settings.dspEqEnabled = true
                        coordinator.player.eqGainsDb = parsed.gains10BandDb
                        coordinator.player.preampDb = parsed.preampDb
                        autoEqStatus = "Imported AutoEq (Preamp \(String(format: "%.1f", parsed.preampDb)) dB)"
                        showAutoEqImport = false
                    } else {
                        autoEqStatus = "Could not parse any Fc/Gain filter bands."
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MochyTheme.buttonFill)
                Spacer()
            }
            .padding(16)
            .background(.black)
            .navigationTitle("Import AutoEq")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAutoEqImport = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct VerticalSliderBar: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let norm = CGFloat((value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound))
            let yPos = (1.0 - norm) * geo.size.height

            ZStack {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 6)
                // Zero center tick
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 12, height: 1)
                // Active fill from center
                let midY = geo.size.height * 0.5
                let barHeight = abs(yPos - midY)
                Capsule()
                    .fill(accent)
                    .frame(width: 6, height: max(2, barHeight))
                    .offset(y: (yPos - midY) * 0.5)
                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .position(x: geo.size.width * 0.5, y: max(7, min(geo.size.height - 7, yPos)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let pct = 1.0 - max(0, min(1, val.location.y / max(1, geo.size.height)))
                        value = range.lowerBound + Float(pct) * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}
