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

        var silentL = [Float](repeating: 0, count: frames)
        var silentR = [Float](repeating: 0, count: frames)
        silentL.withUnsafeMutableBufferPointer { lBuf in
            silentR.withUnsafeMutableBufferPointer { rBuf in
                fx.process(left: lBuf.baseAddress!, right: rBuf.baseAddress!, frames: frames)
            }
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
}
