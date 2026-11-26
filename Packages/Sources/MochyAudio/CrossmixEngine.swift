import Foundation
import MochyDatabase
import MochyDSP

public enum CrossmixCategory: String, Sendable, Equatable {
    case everyday
    case lift
    case fall
    case flavour
}

/// All 19 AI DJ transition styles matching Mochy Music's `CrossmixStyles.kt`.
public enum CrossmixStyle: String, CaseIterable, Codable, Sendable {
    // Everyday
    case silkBlend
    case bassSwap
    case filterSweep
    case echoOut
    // Lift (energy increases)
    case highPassLift
    case backspin
    case loopRoll
    case riserBuild
    // Fall (energy drops)
    case tapeStop
    case powerDown
    case downlifter
    // DJ Flavour
    case dubThrow
    case reverbWash
    case rewindWash
    case stutterGate
    case phaserGlide
    case lofiMelt
    case spatialOrbit
    case dopplerPass

    public var category: CrossmixCategory {
        switch self {
        case .silkBlend, .bassSwap, .filterSweep, .echoOut:
            return .everyday
        case .highPassLift, .backspin, .loopRoll, .riserBuild:
            return .lift
        case .tapeStop, .powerDown, .downlifter:
            return .fall
        case .dubThrow, .reverbWash, .rewindWash, .stutterGate, .phaserGlide, .lofiMelt, .spatialOrbit, .dopplerPass:
            return .flavour
        }
    }

    /// Computes DSP parameter curves (`progress` in `0...1`) for both outgoing and incoming decks.
    public func deckParameters(
        progress tRaw: Float,
        bpm: Double = 120,
        outVoiceLevel: Double = 1.0,
        outBassLevel: Double = 1.0,
        inVoiceLevel: Double = 1.0,
        inBassLevel: Double = 1.0
    ) -> (outgoing: MochyFXParameters, incoming: MochyFXParameters) {
        let t = min(1.0, max(0.0, tRaw))
        let beatMs = Float(60_000.0 / max(60.0, bpm))

        var outFx = MochyFXParameters()
        var inFx = MochyFXParameters()

        // Equal-power fade curve default
        outFx.crossmixGain = cosf(t * .pi * 0.5)
        inFx.crossmixGain = sinf(t * .pi * 0.5)

        outFx.vocalCenterCut = Float(max(0, 1.0 - outVoiceLevel)) * t
        outFx.bassCut = Float(max(0, 1.0 - outBassLevel)) * t
        inFx.vocalCenterCut = Float(max(0, 1.0 - inVoiceLevel)) * (1.0 - t)
        inFx.bassCut = Float(max(0, 1.0 - inBassLevel)) * (1.0 - t)

        switch self {
        case .silkBlend:
            break
        case .bassSwap:
            if t >= 0.45 {
                outFx.bassCut = max(outFx.bassCut, min(1.0, (t - 0.45) * 4.0))
                inFx.bassCut = 0
            } else {
                inFx.bassCut = 1.0
            }
        case .filterSweep:
            outFx.highCutHz = 20_000 - t * 19_200
            inFx.lowCutHz = 1_400 * (1.0 - t)
        case .echoOut:
            outFx.echoDelayMs = beatMs * 0.5
            outFx.echoMix = min(0.75, t * 1.1)
        case .highPassLift, .riserBuild:
            outFx.lowCutHz = 25 + t * 2_400
            outFx.reverbMix = t * 0.35
        case .backspin, .rewindWash:
            outFx.echoDelayMs = beatMs * 0.25
            outFx.echoMix = t * 0.65
            outFx.highCutHz = 18_000 - t * 14_000
        case .loopRoll, .stutterGate:
            let gatePulse = (sinf(t * .pi * 16) > 0) ? Float(1.0) : Float(0.25)
            outFx.crossmixGain *= gatePulse
        case .tapeStop, .powerDown, .downlifter:
            outFx.highCutHz = max(180, 18_000 * powf(1.0 - t, 1.8))
            outFx.crushMix = t * 0.4
        case .dubThrow, .reverbWash:
            outFx.echoDelayMs = beatMs * 0.75
            outFx.echoMix = min(0.85, sinf(t * .pi) * 0.9)
            outFx.reverbMix = min(0.75, t * 0.85)
        case .phaserGlide:
            outFx.flangerMix = sinf(t * .pi) * 0.8
            inFx.flangerMix = (1.0 - t) * 0.5
        case .lofiMelt:
            outFx.crushMix = t * 0.75
            outFx.warmth = t * 0.6
            outFx.highCutHz = 12_000 - t * 9_500
        case .spatialOrbit, .dopplerPass:
            outFx.orbitRateHz = 0.25 + t * 0.6
            inFx.orbitRateHz = 0.4 * (1.0 - t)
        }

        return (outFx, inFx)
    }
}

public struct TrackAudioProfile: Codable, Sendable, Equatable {
    public let bpm: Double
    public let averageRMS: Float
    public let introSeconds: Double
    public let outroStartSeconds: Double
}

public struct CrossmixPlan: Sendable, Equatable {
    public let style: CrossmixStyle
    public let durationSeconds: Double
    public let outStartSeconds: Double
    public let inStartSeconds: Double
    public let bpm: Double
}

public enum CrossmixAnalyzer {
    public static func analyze(monoPCM: [Float], sampleRate: Double, durationSeconds: Double) -> TrackAudioProfile {
        guard !monoPCM.isEmpty, sampleRate > 0 else {
            return TrackAudioProfile(bpm: 120, averageRMS: 0.2, introSeconds: 0, outroStartSeconds: max(0, durationSeconds - 8))
        }
        var sumSq: Double = 0
        for s in monoPCM { sumSq += Double(s * s) }
        let rms = Float(sqrt(sumSq / Double(monoPCM.count)))
        let estimatedBpm = estimateTempoBPM(monoPCM: monoPCM, sampleRate: sampleRate)
        return TrackAudioProfile(
            bpm: estimatedBpm,
            averageRMS: rms,
            introSeconds: 0,
            outroStartSeconds: max(0, durationSeconds - 8.0)
        )
    }

    private static func estimateTempoBPM(monoPCM: [Float], sampleRate: Double) -> Double {
        let hop = max(1, Int(sampleRate * 0.02)) // 50 Hz envelope
        var env: [Float] = []
        var idx = 0
        let limit = min(monoPCM.count, Int(sampleRate * 30))
        while idx + hop <= limit {
            var e: Float = 0
            for i in idx..<(idx + hop) { e += abs(monoPCM[i]) }
            env.append(e / Float(hop))
            idx += hop
        }
        guard env.count > 60 else { return 120 }

        var bestBpm = 120.0
        var bestCorr: Float = -1
        for bpm in stride(from: 75.0, through: 165.0, by: 5.0) {
            let lagFrames = Int((60.0 / bpm) * 50.0)
            guard lagFrames > 0, lagFrames < env.count else { continue }
            var corr: Float = 0
            for i in 0..<(env.count - lagFrames) {
                corr += env[i] * env[i + lagFrames]
            }
            if corr > bestCorr {
                bestCorr = corr
                bestBpm = bpm
            }
        }
        return bestBpm
    }
}

public enum CrossmixPlanner {
    public static func plan(
        from outgoing: TrackAudioProfile,
        to incoming: TrackAudioProfile,
        durationSeconds: Double = 6.0,
        customTransition: PlaylistTransition? = nil
    ) -> CrossmixPlan {
        if let custom = customTransition {
            let parsedStyle = custom.outEffect.flatMap(CrossmixStyle.init(rawValue:)) ?? .bassSwap
            return CrossmixPlan(
                style: parsedStyle,
                durationSeconds: max(1.0, Double(custom.durationMs) / 1000.0),
                outStartSeconds: Double(custom.outStartMs) / 1000.0,
                inStartSeconds: Double(custom.inStartMs) / 1000.0,
                bpm: outgoing.bpm
            )
        }

        let delta = incoming.averageRMS - outgoing.averageRMS
        let chosen: CrossmixStyle
        if delta > 0.06 {
            chosen = .highPassLift
        } else if delta < -0.06 {
            chosen = .echoOut
        } else if abs(outgoing.bpm - incoming.bpm) <= 8 {
            chosen = .bassSwap
        } else {
            chosen = .silkBlend
        }

        return CrossmixPlan(
            style: chosen,
            durationSeconds: durationSeconds,
            outStartSeconds: outgoing.outroStartSeconds,
            inStartSeconds: incoming.introSeconds,
            bpm: outgoing.bpm
        )
    }
}
