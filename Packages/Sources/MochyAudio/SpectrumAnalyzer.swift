import Accelerate
import Foundation
import os

/// Real-time 32-band logarithmic FFT spectrum analyzer powered by Apple `Accelerate` (`vDSP`).
/// Zero heap allocations on the audio render thread; UI polls lock-protected snapshots at 30–60 Hz.
public final class SpectrumAnalyzer: @unchecked Sendable {
    public static let fftSize = 1024
    public static let halfSize = fftSize / 2
    public static let binCount = 32

    private let dftSetup: OpaquePointer?
    private var window: [Float]
    private var ringBuffer: [Float]
    private var ringWriteIndex = 0
    private var sampleRate: Float

    // Pre-allocated scratch buffers for audio-thread FFT execution.
    private var windowed: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var magnitudes: [Float]
    private var localBins: [Float]

    // Lock-protected UI-facing snapshot.
    private var snapshotLock = os_unfair_lock()
    private var publishedBins: [Float] = Array(repeating: 0, count: binCount)
    private var publishedBassEnergy: Float = 0

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = Float(max(8_000, sampleRate))
        self.dftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(Self.fftSize), .FORWARD)
        self.window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&self.window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))

        self.ringBuffer = [Float](repeating: 0, count: Self.fftSize)
        self.windowed = [Float](repeating: 0, count: Self.fftSize)
        self.realIn = [Float](repeating: 0, count: Self.halfSize)
        self.imagIn = [Float](repeating: 0, count: Self.halfSize)
        self.realOut = [Float](repeating: 0, count: Self.halfSize)
        self.imagOut = [Float](repeating: 0, count: Self.halfSize)
        self.magnitudes = [Float](repeating: 0, count: Self.halfSize)
        self.localBins = [Float](repeating: 0, count: Self.binCount)
    }

    deinit {
        if let dftSetup {
            vDSP_DFT_DestroySetup(dftSetup)
        }
    }

    public func updateSampleRate(_ rate: Double) {
        os_unfair_lock_lock(&snapshotLock)
        sampleRate = Float(max(8_000, rate))
        os_unfair_lock_unlock(&snapshotLock)
    }

    public func reset() {
        for i in 0..<Self.fftSize { ringBuffer[i] = 0 }
        ringWriteIndex = 0
        for i in 0..<Self.binCount { localBins[i] = 0 }
        os_unfair_lock_lock(&snapshotLock)
        for i in 0..<Self.binCount { publishedBins[i] = 0 }
        publishedBassEnergy = 0
        os_unfair_lock_unlock(&snapshotLock)
    }

    /// Consumes mono/left Float32 PCM frames directly on the audio render thread without allocating.
    public func consume(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0, let dftSetup else { return }

        let size = Self.fftSize
        var idx = ringWriteIndex
        for i in 0..<count {
            ringBuffer[idx] = samples[i]
            idx += 1
            if idx == size { idx = 0 }
        }
        ringWriteIndex = idx

        // Unroll ring buffer in chronological order into `windowed` and apply Hann window.
        let tailCount = size - idx
        for i in 0..<tailCount {
            windowed[i] = ringBuffer[idx + i] * window[i]
        }
        for i in 0..<idx {
            windowed[tailCount + i] = ringBuffer[i] * window[tailCount + i]
        }

        // Pack real input into split even/odd buffers for `vDSP_DFT_zrop`.
        let half = Self.halfSize
        for i in 0..<half {
            realIn[i] = windowed[i * 2]
            imagIn[i] = windowed[i * 2 + 1]
        }

        vDSP_DFT_Execute(dftSetup, realIn, imagIn, &realOut, &imagOut)

        // Compute linear magnitudes of complex bins (skip DC at index 0).
        let scale = 1.0 / Float(size)
        magnitudes[0] = 0
        for i in 1..<half {
            let re = realOut[i] * scale
            let im = imagOut[i] * scale
            magnitudes[i] = sqrtf(re * re + im * im)
        }

        // Group FFT bins logarithmically across 32 perceptual bands (25 Hz .. 18 kHz).
        let fs = sampleRate
        let minFreq: Float = 25.0
        let maxFreq: Float = min(18_000.0, fs * 0.45)
        let ratio = maxFreq / minFreq
        let binHz = fs / Float(size)

        for b in 0..<Self.binCount {
            let f0 = minFreq * powf(ratio, Float(b) / Float(Self.binCount))
            let f1 = minFreq * powf(ratio, Float(b + 1) / Float(Self.binCount))
            let startBin = max(1, min(half - 1, Int(floorf(f0 / binHz))))
            let endBin = max(startBin + 1, min(half, Int(ceilf(f1 / binHz))))

            var peak: Float = 0
            for k in startBin..<endBin {
                if magnitudes[k] > peak { peak = magnitudes[k] }
            }

            // Convert amplitude to normalized dB scale [-65 dB .. 0 dB] -> [0 .. 1].
            let db = 20.0 * log10f(max(peak, 1e-6))
            let normalized = max(0.0, min(1.0, (db + 65.0) / 55.0))
            // Fast attack, smooth decay envelope.
            let prev = localBins[b]
            localBins[b] = normalized > prev
                ? (prev * 0.35 + normalized * 0.65)
                : (prev * 0.78 + normalized * 0.22)
        }

        let bass = (localBins[0] + localBins[1] + localBins[2] + localBins[3]) * 0.25

        if os_unfair_lock_trylock(&snapshotLock) {
            for i in 0..<Self.binCount {
                publishedBins[i] = localBins[i]
            }
            publishedBassEnergy = bass
            os_unfair_lock_unlock(&snapshotLock)
        }
    }

    public func snapshot() -> (bins: [Float], bassEnergy: Float) {
        os_unfair_lock_lock(&snapshotLock)
        let bins = publishedBins
        let bass = publishedBassEnergy
        os_unfair_lock_unlock(&snapshotLock)
        return (bins, bass)
    }
}
