import Foundation
import XCTest
@testable import MochyDSP

final class MochyDSPTests: XCTestCase {
    func testStageAndFXEnginesProcessAudioWithoutNaN() {
        XCTAssertTrue(MochyStageEngine.ensureHRTFLoaded())

        let stage = MochyStageEngine(sampleRate: 48_000, channels: 2)
        var stageParams = StageParameters()
        stageParams.enabled = true
        stage.update(stageParams)

        let fx = MochyFXEngine(sampleRate: 48_000)
        var fxParams = MochyFXParameters()
        fxParams.enabled = true
        fxParams.eqGainsDb[0] = 3.0
        fxParams.reverbMix = 0.25
        fx.update(fxParams)

        let frames = 512
        var left = (0..<frames).map { i in sinf(Float(i) * 2 * .pi * 440.0 / 48_000.0) * 0.5 }
        var right = left

        left.withUnsafeMutableBufferPointer { lBuf in
            right.withUnsafeMutableBufferPointer { rBuf in
                fx.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: frames)
                _ = stage.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: frames)
            }
        }

        XCTAssertTrue(left.allSatisfy(\.isFinite))
        XCTAssertTrue(right.allSatisfy(\.isFinite))
        XCTAssertFalse(fx.isSilent)
        XCTAssertGreaterThan(fx.currentLUFS, -60)

        var silentL = [Float](repeating: 0, count: 4096)
        var silentR = [Float](repeating: 0, count: 4096)
        for _ in 0..<8 {
            silentL.withUnsafeMutableBufferPointer { lBuf in
                silentR.withUnsafeMutableBufferPointer { rBuf in
                    fx.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: 4096)
                }
            }
            silentL = [Float](repeating: 0, count: 4096)
            silentR = [Float](repeating: 0, count: 4096)
        }
        XCTAssertTrue(fx.isSilent)
    }

    func testAutoEqParserAndAudioPassBlockers() {
        let eqText = """
        Preamp: -4.5 dB
        Filter 1: ON PK Fc 62 Hz Gain 3.0 dB Q 1.4
        Filter 2: ON PK Fc 4000 Hz Gain -2.5 dB Q 2.0
        """
        let preset = AutoEqRepository.parseAutoEqText(eqText, name: "TestHeadphone")
        XCTAssertEqual(preset?.preampDb, -4.5)
        XCTAssertEqual(preset?.gains10BandDb[1], 3.0)
        XCTAssertEqual(preset?.gains10BandDb[7], -2.5)

        let blockers = AudioPassController.activeBlockers(
            eqEnabled: true,
            stageEnabled: false,
            orbitEnabled: true,
            crossmixActive: false
        )
        XCTAssertEqual(blockers.count, 2)
    }

    func testConcurrentFxUpdatesAndLarge8192FrameStageProcessingNeverProduceNaN() {
        XCTAssertTrue(MochyStageEngine.ensureHRTFLoaded())
        let fx = MochyFXEngine(sampleRate: 48_000)
        let stage = MochyStageEngine(sampleRate: 48_000, channels: 2)
        var stg = StageParameters()
        stg.enabled = true
        stage.update(stg)

        let group = DispatchGroup()
        let writerQ = DispatchQueue(label: "test.dsp.writer")
        let audioQ = DispatchQueue(label: "test.dsp.audio")
        let allFinite = LockedBool(true)

        group.enter()
        writerQ.async {
            for i in 0..<1000 {
                var p = MochyFXParameters()
                p.enabled = true
                p.eqGainsDb[i % 10] = Float((i % 13) - 6)
                p.bassBoostDb = Float(i % 6)
                p.reverbMix = Float(i % 5) * 0.1
                p.flangerMix = (i % 2 == 0) ? 0.45 : 0.0
                fx.update(p)
            }
            group.leave()
        }

        group.enter()
        audioQ.async {
            let frames = 8192 // Exceeds old 4096 hard cap — exercises 1024-frame slicing
            var left = [Float](repeating: 0, count: frames)
            var right = [Float](repeating: 0, count: frames)
            for block in 0..<24 {
                for i in 0..<frames {
                    let s = sinf(Float(block * frames + i) * 2.0 * .pi * 330.0 / 48_000.0) * 0.4
                    left[i] = s
                    right[i] = s
                }
                left.withUnsafeMutableBufferPointer { lBuf in
                    right.withUnsafeMutableBufferPointer { rBuf in
                        fx.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: frames)
                        _ = stage.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: frames)
                    }
                }
                if !left.allSatisfy(\.isFinite) || !right.allSatisfy(\.isFinite) {
                    allFinite.set(false)
                }
            }
            group.leave()
        }

        group.wait()
        XCTAssertTrue(allFinite.get())
        XCTAssertEqual(stage.currentLevels().count, 6)
    }

    func testFlangerEffectModulatesAudioSignal() {
        let frames = 2048
        let drySignal = (0..<frames).map { i in sinf(Float(i) * 2.0 * .pi * 440.0 / 48_000.0) * 0.4 }

        let dryFx = MochyFXEngine(sampleRate: 48_000)
        var dryParams = MochyFXParameters()
        dryParams.enabled = true
        dryParams.flangerMix = 0.0
        dryFx.update(dryParams)

        var dryL = drySignal
        var dryR = drySignal
        dryL.withUnsafeMutableBufferPointer { l in
            dryR.withUnsafeMutableBufferPointer { r in
                dryFx.process(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
            }
        }

        let wetFx = MochyFXEngine(sampleRate: 48_000)
        var wetParams = MochyFXParameters()
        wetParams.enabled = true
        wetParams.flangerMix = 0.85
        wetFx.update(wetParams)

        var wetL = drySignal
        var wetR = drySignal
        wetL.withUnsafeMutableBufferPointer { l in
            wetR.withUnsafeMutableBufferPointer { r in
                wetFx.process(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
            }
        }

        var diffEnergy: Float = 0
        for i in 512..<frames {
            let d = wetL[i] - dryL[i]
            diffEnergy += d * d
        }
        XCTAssertGreaterThan(diffEnergy, 0.5)
    }
}

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var val: Bool
    init(_ v: Bool) { self.val = v }
    func set(_ v: Bool) { lock.lock(); val = v; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return val }
}
