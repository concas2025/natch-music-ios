import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox
import MochyDSP
import os

/// Inline real-time C++ DSP context attached to an `AVPlayerItem` via `MTAudioProcessingTap`.
/// Processes BOTH remote HTTP proxy streams and local `file://` assets directly before hardware output.
public final class RealtimeDeckDSPContext: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var fxEngine: MochyFXEngine
    private var stageEngine: MochyStageEngine?
    private let spectrumAnalyzer: SpectrumAnalyzer?

    private var currentSampleRate: Double = 48_000
    private var latestFXParams = MochyFXParameters()
    private var latestStageParams = StageParameters()
    private var bypassAllDSP = false
    private var stageEnabled = false

    // Stream format discovered during `prepare`.
    private var formatIsFloat = true
    private var formatIsSignedInt16 = false
    private var formatChannels: UInt32 = 2
    private var formatIsNonInterleaved = true

    // Pre-allocated deinterleave / conversion scratch buffers (resized only in `prepare`, never in `process`).
    private var scratchL: [Float] = Array(repeating: 0, count: 4096)
    private var scratchR: [Float] = Array(repeating: 0, count: 4096)

    public init(enableStageAndSpectrum: Bool) {
        self.fxEngine = MochyFXEngine(sampleRate: 48_000)
        if enableStageAndSpectrum {
            self.stageEngine = MochyStageEngine(sampleRate: 48_000, channels: 2)
            self.spectrumAnalyzer = SpectrumAnalyzer(sampleRate: 48_000)
        } else {
            self.stageEngine = nil
            self.spectrumAnalyzer = nil
        }
    }

    public func updateFX(_ params: MochyFXParameters, bypassAll: Bool) {
        os_unfair_lock_lock(&lock)
        latestFXParams = params
        bypassAllDSP = bypassAll
        let fx = fxEngine
        os_unfair_lock_unlock(&lock)
        fx.update(params)
    }

    public func updateStage(_ params: StageParameters, enabled: Bool) {
        os_unfair_lock_lock(&lock)
        latestStageParams = params
        stageEnabled = enabled
        let stage = stageEngine
        os_unfair_lock_unlock(&lock)
        stage?.update(params)
    }

    public func resetState() {
        os_unfair_lock_lock(&lock)
        let fx = fxEngine
        let stage = stageEngine
        os_unfair_lock_unlock(&lock)
        fx.reset()
        stage?.clear()
        spectrumAnalyzer?.reset()
    }

    public func spectrumSnapshot() -> (bins: [Float], bassEnergy: Float) {
        spectrumAnalyzer?.snapshot() ?? (Array(repeating: 0, count: SpectrumAnalyzer.binCount), 0)
    }

    public func stageLevels() -> [Float] {
        os_unfair_lock_lock(&lock)
        let stage = stageEngine
        os_unfair_lock_unlock(&lock)
        return stage?.currentLevels() ?? Array(repeating: 0, count: 6)
    }

    public var currentLUFS: Float {
        os_unfair_lock_lock(&lock)
        let fx = fxEngine
        os_unfair_lock_unlock(&lock)
        return fx.currentLUFS
    }

    public var isSilent: Bool {
        os_unfair_lock_lock(&lock)
        let fx = fxEngine
        os_unfair_lock_unlock(&lock)
        return fx.isSilent
    }

    fileprivate func prepare(maxFrames: Int, format: AudioStreamBasicDescription) {
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let needed = max(4096, maxFrames)

        os_unfair_lock_lock(&lock)
        formatIsFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
        formatIsSignedInt16 = (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 && format.mBitsPerChannel == 16
        formatChannels = max(1, format.mChannelsPerFrame)
        formatIsNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if scratchL.count < needed {
            scratchL = Array(repeating: 0, count: needed)
            scratchR = Array(repeating: 0, count: needed)
        }

        if abs(rate - currentSampleRate) > 1.0 {
            currentSampleRate = rate
            let newFX = MochyFXEngine(sampleRate: rate)
            newFX.update(latestFXParams)
            fxEngine = newFX
            if stageEngine != nil {
                let newStage = MochyStageEngine(sampleRate: Int(rate), channels: 2)
                newStage.update(latestStageParams)
                stageEngine = newStage
            }
            spectrumAnalyzer?.updateSampleRate(rate)
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Executes inline C++ DSP and Accelerate FFT on CoreMedia's decoded audio buffer list.
    public func processAudioBufferList(_ bufferListInOut: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }

        os_unfair_lock_lock(&lock)
        let bypass = bypassAllDSP
        let runStage = !bypass && stageEnabled
        let fx = fxEngine
        let stage = stageEngine
        let isFloat = formatIsFloat
        let isInt16 = formatIsSignedInt16
        let isNonInterleaved = formatIsNonInterleaved
        os_unfair_lock_unlock(&lock)

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        guard !buffers.isEmpty else { return }

        // Fast path: non-interleaved Float32 stereo (standard CoreMedia AVPlayer decode format on iOS/macOS).
        if isFloat && isNonInterleaved && buffers.count >= 2,
           let lRaw = buffers[0].mData,
           let rRaw = buffers[1].mData {
            let lPtr = lRaw.assumingMemoryBound(to: Float.self)
            let rPtr = rRaw.assumingMemoryBound(to: Float.self)
            if !bypass {
                fx.process(left: lPtr, right: rPtr, frames: frameCount)
                if runStage {
                    _ = stage?.process(left: lPtr, right: rPtr, frames: frameCount)
                }
            }
            spectrumAnalyzer?.consume(samples: lPtr, count: frameCount)
            return
        }

        // Fallback paths: interleaved Float32, mono Float32, or Int16 PCM processed in chunks via pre-allocated scratch buffers.
        let capacity = min(scratchL.count, scratchR.count)
        guard capacity > 0 else { return }

        if isFloat && buffers.count == 1, let raw = buffers[0].mData {
            let channels = max(1, Int(buffers[0].mNumberChannels))
            let samples = raw.assumingMemoryBound(to: Float.self)

            var offset = 0
            while offset < frameCount {
                let n = min(capacity, frameCount - offset)
                scratchL.withUnsafeMutableBufferPointer { lBuf in
                    scratchR.withUnsafeMutableBufferPointer { rBuf in
                        guard let lPtr = lBuf.baseAddress, let rPtr = rBuf.baseAddress else { return }
                        if channels >= 2 {
                            for i in 0..<n {
                                let base = (offset + i) * channels
                                lPtr[i] = samples[base]
                                rPtr[i] = samples[base + 1]
                            }
                        } else {
                            for i in 0..<n {
                                let s = samples[offset + i]
                                lPtr[i] = s
                                rPtr[i] = s
                            }
                        }

                        if !bypass {
                            fx.process(left: lPtr, right: rPtr, frames: n)
                            if runStage {
                                _ = stage?.process(left: lPtr, right: rPtr, frames: n)
                            }
                        }
                        spectrumAnalyzer?.consume(samples: lPtr, count: n)

                        if !bypass {
                            if channels >= 2 {
                                for i in 0..<n {
                                    let base = (offset + i) * channels
                                    samples[base] = lPtr[i]
                                    samples[base + 1] = rPtr[i]
                                }
                            } else {
                                for i in 0..<n {
                                    samples[offset + i] = (lPtr[i] + rPtr[i]) * 0.5
                                }
                            }
                        }
                    }
                }
                offset += n
            }
        } else if isInt16 && buffers.count == 1, let raw = buffers[0].mData {
            let channels = max(1, Int(buffers[0].mNumberChannels))
            let samples = raw.assumingMemoryBound(to: Int16.self)

            var offset = 0
            while offset < frameCount {
                let n = min(capacity, frameCount - offset)
                scratchL.withUnsafeMutableBufferPointer { lBuf in
                    scratchR.withUnsafeMutableBufferPointer { rBuf in
                        guard let lPtr = lBuf.baseAddress, let rPtr = rBuf.baseAddress else { return }
                        if channels >= 2 {
                            for i in 0..<n {
                                let base = (offset + i) * channels
                                lPtr[i] = Float(samples[base]) / 32768.0
                                rPtr[i] = Float(samples[base + 1]) / 32768.0
                            }
                        } else {
                            for i in 0..<n {
                                let s = Float(samples[offset + i]) / 32768.0
                                lPtr[i] = s
                                rPtr[i] = s
                            }
                        }

                        if !bypass {
                            fx.process(left: lPtr, right: rPtr, frames: n)
                            if runStage {
                                _ = stage?.process(left: lPtr, right: rPtr, frames: n)
                            }
                        }
                        spectrumAnalyzer?.consume(samples: lPtr, count: n)

                        if !bypass {
                            if channels >= 2 {
                                for i in 0..<n {
                                    let base = (offset + i) * channels
                                    samples[base] = Int16(max(-1.0, min(1.0, lPtr[i])) * 32767.0)
                                    samples[base + 1] = Int16(max(-1.0, min(1.0, rPtr[i])) * 32767.0)
                                }
                            } else {
                                for i in 0..<n {
                                    let mono = (lPtr[i] + rPtr[i]) * 0.5
                                    samples[offset + i] = Int16(max(-1.0, min(1.0, mono)) * 32767.0)
                                }
                            }
                        }
                    }
                }
                offset += n
            }
        }
    }
}

/// Builds an `AVMutableAudioMix` binding an `MTAudioProcessingTap` directly onto an `AVAsset`'s audio track.
public enum AudioProcessingTapBinder {
    public static func makeAudioMix(for asset: AVAsset, context: RealtimeDeckDSPContext) async -> AVMutableAudioMix? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let audioTrack = tracks.first else {
            return nil
        }

        let retainedClientInfo = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedClientInfo,
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )

        var tapOut: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tapOut
        )
        guard status == noErr, let tap = tapOut?.takeRetainedValue() else {
            // If creation failed, `finalize` will not fire, so balance the retain here.
            Unmanaged<RealtimeDeckDSPContext>.fromOpaque(retainedClientInfo).release()
            return nil
        }

        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [inputParams]
        return mix
    }
}

private let tapInitCallback: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { tap in
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<RealtimeDeckDSPContext>.fromOpaque(storage).release()
}

private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, processingFormat in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<RealtimeDeckDSPContext>.fromOpaque(storage).takeUnretainedValue()
    context.prepare(maxFrames: Int(maxFrames), format: processingFormat.pointee)
}

private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { _ in
    // Keep DSP parameter state intact across pause/seek; buffers are freed in deinit.
}

private let tapProcessCallback: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    var timeRange = CMTimeRange.zero
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        &timeRange,
        numberFramesOut
    )
    guard status == noErr else { return }
    let frameCount = Int(numberFramesOut.pointee)
    guard frameCount > 0 else { return }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<RealtimeDeckDSPContext>.fromOpaque(storage).takeUnretainedValue()
    context.processAudioBufferList(bufferListInOut, frameCount: frameCount)
}
