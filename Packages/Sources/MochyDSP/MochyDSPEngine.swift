import CMochyDSP
import Foundation

// MARK: - 3D Room Spatializer (C++17 Mochy Stage + KEMAR HRTF)

public struct StageParameters: Sendable, Equatable {
    public var enabled: Bool = false
    public var headphonesMode: Bool = true
    public var roomWidthMeters: Float = 6.0
    public var roomDepthMeters: Float = 7.0
    public var roomHeightMeters: Float = 3.2
    public var absorb: Float = 0.35
    public var damp: Float = 0.40
    public var roomAmount: Float = 0.55
    public var yawRadians: Float = 0.0
    public var masterGain: Float = 1.0

    // Normalized placements matching Stage Engine's 6 kinds
    public var vocalPos: SIMD3<Float> = SIMD3(0, 0.3, 1.8)
    public var leftPos: SIMD3<Float> = SIMD3(-1.8, 0.1, 1.5)
    public var rightPos: SIMD3<Float> = SIMD3(1.8, 0.1, 1.5)
    public var subPos: SIMD3<Float> = SIMD3(0, -0.8, 1.4)

    public init() {}

    public func packedArray() -> [Float] {
        var params = [Float](repeating: 0, count: Int(MOCHY_STAGE_PARAM_COUNT))
        params[0] = enabled ? 1.0 : 0.0
        params[1] = headphonesMode ? 0.0 : 1.0
        params[2] = roomWidthMeters
        params[3] = roomDepthMeters
        params[4] = roomHeightMeters
        params[5] = absorb
        params[6] = damp
        params[7] = roomAmount
        params[8] = 0 // listener X
        params[9] = 0 // listener Y
        params[10] = 0 // listener Z
        params[11] = yawRadians
        params[12] = masterGain

        func writeObject(kind: Int, pos: SIMD3<Float>, gain: Float = 1.0, width: Float = 0.4) {
            let offset = 13 + (kind * 4) * 5
            guard offset + 4 < params.count else { return }
            params[offset + 0] = pos.x
            params[offset + 1] = pos.y
            params[offset + 2] = pos.z
            params[offset + 3] = gain
            params[offset + 4] = width
        }

        writeObject(kind: 0, pos: vocalPos, gain: 1.0, width: 0.25)
        writeObject(kind: 1, pos: SIMD3(0, 0, 1.6), gain: 0.85, width: 0.5)
        writeObject(kind: 2, pos: leftPos, gain: 1.0, width: 0.35)
        writeObject(kind: 3, pos: rightPos, gain: 1.0, width: 0.35)
        writeObject(kind: 4, pos: SIMD3(0, 0.5, -1.6), gain: 0.7, width: 1.0)
        writeObject(kind: 5, pos: subPos, gain: 0.9, width: 0.4)
        return params
    }
}

public final class MochyStageEngine {
    private var handle: UnsafeMutableRawPointer?

    public init(sampleRate: Int = 48_000, channels: Int = 2) {
        _ = Self.ensureHRTFLoaded()
        self.handle = mochy_stage_create(Int32(sampleRate), Int32(channels))
    }

    deinit {
        if let handle {
            mochy_stage_destroy(handle)
        }
    }

    @discardableResult
    public static func ensureHRTFLoaded() -> Bool {
        guard let url = Bundle.module.url(forResource: "stage_hrtf", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        return data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return mochy_stage_load_hrtf(ptr, data.count)
        }
    }

    public func update(_ parameters: StageParameters) {
        guard let handle else { return }
        let array = parameters.packedArray()
        array.withUnsafeBufferPointer { buf in
            mochy_stage_set_params(handle, buf.baseAddress, Int32(array.count))
        }
    }

    public func clear() {
        guard let handle else { return }
        mochy_stage_clear(handle)
    }

    @discardableResult
    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        guard let handle else { return true }
        return mochy_stage_process_f32(handle, left, right, Int32(frames))
    }

    public func currentLevels() -> [Float] {
        guard let handle else { return Array(repeating: 0, count: 6) }
        var out = [Float](repeating: 0, count: Int(MOCHY_STAGE_LEVEL_COUNT))
        out.withUnsafeMutableBufferPointer { buf in
            mochy_stage_levels(handle, buf.baseAddress)
        }
        return out
    }
}

// MARK: - FX Bus Wrapper (10-Band EQ + Tone + Reverb + 8D + Crossmix)

public struct MochyFXParameters: Sendable, Equatable {
    public var enabled: Bool = true
    public var eqGainsDb: [Float] = Array(repeating: 0, count: 10)
    public var bassBoostDb: Float = 0
    public var trebleBoostDb: Float = 0
    public var warmth: Float = 0
    public var reverbMix: Float = 0
    public var orbitRateHz: Float = 0
    public var replayGainDb: Float = 0
    public var limiterEnabled: Bool = true

    public var crossmixGain: Float = 1.0
    public var lowCutHz: Float = 0
    public var highCutHz: Float = 20_000
    public var bassCut: Float = 0
    public var vocalCenterCut: Float = 0
    public var sideCut: Float = 0
    public var echoMix: Float = 0
    public var echoDelayMs: Float = 250
    public var flangerMix: Float = 0
    public var crushMix: Float = 0

    public init() {}

    func toC() -> MochyFxParams {
        var c = MochyFxParams()
        c.enabled = enabled
        let padded = eqGainsDb + Array(repeating: Float(0), count: max(0, 10 - eqGainsDb.count))
        c.eq_gains_db = (
            padded[0], padded[1], padded[2], padded[3], padded[4],
            padded[5], padded[6], padded[7], padded[8], padded[9]
        )
        c.bass_boost_db = bassBoostDb
        c.treble_boost_db = trebleBoostDb
        c.warmth = warmth
        c.reverb_mix = reverbMix
        c.orbit_rate_hz = orbitRateHz
        c.replay_gain_db = replayGainDb
        c.limiter_enabled = limiterEnabled
        c.crossmix_gain = crossmixGain
        c.low_cut_hz = lowCutHz
        c.high_cut_hz = highCutHz
        c.bass_cut = bassCut
        c.vocal_center_cut = vocalCenterCut
        c.side_cut = sideCut
        c.echo_mix = echoMix
        c.echo_delay_ms = echoDelayMs
        c.flanger_mix = flangerMix
        c.crush_mix = crushMix
        return c
    }
}

public final class MochyFXEngine {
    private var handle: UnsafeMutableRawPointer?

    public init(sampleRate: Double = 48_000) {
        self.handle = mochy_fx_create(sampleRate)
    }

    deinit {
        if let handle {
            mochy_fx_destroy(handle)
        }
    }

    public func update(_ parameters: MochyFXParameters) {
        guard let handle else { return }
        var c = parameters.toC()
        mochy_fx_update(handle, &c)
    }

    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        guard let handle else { return }
        mochy_fx_process(handle, left, right, Int32(frames))
    }

    public var currentLUFS: Float {
        guard let handle else { return -70 }
        return mochy_fx_get_lufs(handle)
    }

    public var isSilent: Bool {
        guard let handle else { return true }
        return mochy_fx_is_silent(handle)
    }
}

// MARK: - AutoEq Headphone Presets & Audio Pass Blocker Guard

public struct AutoEqPreset: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let preampDb: Float
    public let gains10BandDb: [Float]
}

public enum AutoEqRepository {
    public static let builtInPresets: [AutoEqPreset] = [
        AutoEqPreset(id: "flat", name: "Flat / Reference", preampDb: 0, gains10BandDb: Array(repeating: 0, count: 10)),
        AutoEqPreset(id: "airpods_pro_2", name: "Apple AirPods Pro 2 (Harman)", preampDb: -2.5, gains10BandDb: [1.5, 2.0, 0.5, -1.0, 0.0, 0.5, 1.5, 1.0, -0.5, 0.5]),
        AutoEqPreset(id: "airpods_max", name: "Apple AirPods Max (Harman)", preampDb: -3.0, gains10BandDb: [2.0, 1.5, 0.0, -1.5, 0.5, 1.5, 2.0, 1.0, 0.0, -0.5]),
        AutoEqPreset(id: "sony_xm5", name: "Sony WH-1000XM5 (Harman)", preampDb: -4.2, gains10BandDb: [-2.0, -4.0, -3.5, -1.5, 0.5, 2.0, 2.5, 1.5, 1.0, 2.0]),
        AutoEqPreset(id: "hd650", name: "Sennheiser HD 650 (Harman)", preampDb: -3.5, gains10BandDb: [4.0, 2.5, 0.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 1.0]),
    ]

    /// Parses standard AutoEq `GraphicEQ:` or `Filter ... Fc ... Hz Gain ... dB` text exports into 10 bands.
    public static func parseAutoEqText(_ raw: String, name: String = "Imported AutoEq") -> AutoEqPreset? {
        let eqCenters: [Double] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        var gains = [Float](repeating: 0, count: 10)
        var preamp: Float = 0
        var matched = false

        let pattern = try! NSRegularExpression(
            pattern: #"Fc\s+([0-9.]+)\s*Hz\s+Gain\s+([-+]?[0-9.]+)\s*dB"#,
            options: [.caseInsensitive]
        )
        for line in raw.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix("preamp:") {
                let num = line.replacingOccurrences(of: "Preamp:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                preamp = Float(num) ?? 0
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = pattern.firstMatch(in: line, range: range),
               let fR = Range(m.range(at: 1), in: line),
               let gR = Range(m.range(at: 2), in: line),
               let freq = Double(line[fR]), let gain = Float(line[gR]) {
                // Assign to nearest octave center
                if let bestIdx = eqCenters.enumerated().min(by: { abs($0.element - freq) < abs($1.element - freq) })?.offset {
                    gains[bestIdx] += gain
                    matched = true
                }
            }
        }
        guard matched else { return nil }
        return AutoEqPreset(id: UUID().uuidString, name: name, preampDb: preamp, gains10BandDb: gains)
    }
}

public struct AudioPassRestoreSnapshot: Codable, Sendable, Equatable {
    public let eqEnabled: Bool
    public let stageEnabled: Bool
    public let orbitEnabled: Bool
    public let crossmixActive: Bool
}

public enum AudioPassController {
    public static func activeBlockers(
        eqEnabled: Bool,
        stageEnabled: Bool,
        orbitEnabled: Bool,
        crossmixActive: Bool
    ) -> [String] {
        var blockers: [String] = []
        if eqEnabled { blockers.append("10-Band Equalizer") }
        if stageEnabled { blockers.append("3D Stage Room") }
        if orbitEnabled { blockers.append("8D Auto-Orbit") }
        if crossmixActive { blockers.append("Crossmix Transition DSP") }
        return blockers
    }

    public static func makeSnapshot(
        eqEnabled: Bool,
        stageEnabled: Bool,
        orbitEnabled: Bool,
        crossmixActive: Bool
    ) -> AudioPassRestoreSnapshot {
        AudioPassRestoreSnapshot(
            eqEnabled: eqEnabled,
            stageEnabled: stageEnabled,
            orbitEnabled: orbitEnabled,
            crossmixActive: crossmixActive
        )
    }
}
