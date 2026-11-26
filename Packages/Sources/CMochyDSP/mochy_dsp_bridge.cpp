#include "mochy_dsp_bridge.h"
#include "engine.h"
#include "hrtf.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr std::array<double, 10> kEqFreqs = {
    31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
};

struct StereoBiquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    double z1L = 0, z2L = 0, z1R = 0, z2R = 0;

    void resetState() {
        z1L = z2L = z1R = z2R = 0.0;
    }

    void setPeaking(double fs, double f0, double q, double gainDb) {
        if (std::abs(gainDb) < 0.05) {
            b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0;
            return;
        }
        double A = std::pow(10.0, gainDb / 40.0);
        double w0 = 2.0 * kPi * std::clamp(f0, 20.0, fs * 0.45) / fs;
        double cosW = std::cos(w0);
        double alpha = std::sin(w0) / (2.0 * q);
        double a0 = 1.0 + alpha / A;
        b0 = (1.0 + alpha * A) / a0;
        b1 = (-2.0 * cosW) / a0;
        b2 = (1.0 - alpha * A) / a0;
        a1 = (-2.0 * cosW) / a0;
        a2 = (1.0 - alpha / A) / a0;
    }

    void setLowPass(double fs, double f0, double q = 0.7071) {
        double w0 = 2.0 * kPi * std::clamp(f0, 30.0, fs * 0.45) / fs;
        double cosW = std::cos(w0);
        double alpha = std::sin(w0) / (2.0 * q);
        double a0 = 1.0 + alpha;
        b0 = ((1.0 - cosW) * 0.5) / a0;
        b1 = (1.0 - cosW) / a0;
        b2 = ((1.0 - cosW) * 0.5) / a0;
        a1 = (-2.0 * cosW) / a0;
        a2 = (1.0 - alpha) / a0;
    }

    void setHighPass(double fs, double f0, double q = 0.7071) {
        double w0 = 2.0 * kPi * std::clamp(f0, 20.0, fs * 0.45) / fs;
        double cosW = std::cos(w0);
        double alpha = std::sin(w0) / (2.0 * q);
        double a0 = 1.0 + alpha;
        b0 = ((1.0 + cosW) * 0.5) / a0;
        b1 = -(1.0 + cosW) / a0;
        b2 = ((1.0 + cosW) * 0.5) / a0;
        a1 = (-2.0 * cosW) / a0;
        a2 = (1.0 - alpha) / a0;
    }

    inline void process(float& l, float& r) {
        double xl = l;
        double yl = b0 * xl + z1L;
        z1L = b1 * xl - a1 * yl + z2L;
        z2L = b2 * xl - a2 * yl;
        l = static_cast<float>(yl);

        double xr = r;
        double yr = b0 * xr + z1R;
        z1R = b1 * xr - a1 * yr + z2R;
        z2R = b2 * xr - a2 * yr;
        r = static_cast<float>(yr);
    }
};

struct MochyStageWrapper {
    static constexpr int kChunkFrames = 1024;

    std::unique_ptr<stage::Engine> engine;
    std::mutex stageMutex;
    std::array<float, MOCHY_STAGE_PARAM_COUNT> stagedParams{};
    int stagedParamCount = 0;
    std::atomic<bool> paramsDirty{false};
    std::atomic<bool> clearRequested{false};
    std::array<std::atomic<float>, MOCHY_STAGE_LEVEL_COUNT> cachedLevels{};

    // Pre-allocated chunk conversion buffers (zero stack bloat & zero heap alloc on audio thread).
    std::array<int16_t, kChunkFrames * 2> inInterleaved{};
    std::array<int16_t, kChunkFrames * 2> outInterleaved{};

    MochyStageWrapper(int sampleRate, int channels)
        : engine(std::make_unique<stage::Engine>(sampleRate, channels)) {
        for (auto& lvl : cachedLevels) {
            lvl.store(0.0f, std::memory_order_relaxed);
        }
    }

    void enqueueParams(const float* params, int count) {
        int clamped = std::min(count, static_cast<int>(MOCHY_STAGE_PARAM_COUNT));
        {
            std::lock_guard<std::mutex> lock(stageMutex);
            std::memcpy(stagedParams.data(), params, static_cast<size_t>(clamped) * sizeof(float));
            stagedParamCount = clamped;
        }
        paramsDirty.store(true, std::memory_order_release);
    }

    void requestClear() {
        clearRequested.store(true, std::memory_order_release);
    }

    bool processF32(float* left, float* right, int frames) {
        if (!engine || !left || !right || frames <= 0) return true;

        if (clearRequested.exchange(false, std::memory_order_acquire)) {
            engine->clear();
        }

        if (paramsDirty.exchange(false, std::memory_order_acquire)) {
            std::unique_lock<std::mutex> lock(stageMutex, std::try_to_lock);
            if (lock.owns_lock()) {
                std::array<float, MOCHY_STAGE_PARAM_COUNT> localCopy = stagedParams;
                int count = stagedParamCount;
                lock.unlock();
                if (count > 0) {
                    engine->setParams(localCopy.data(), count);
                }
            } else {
                // Retry on next audio render quantum without blocking the realtime thread.
                paramsDirty.store(true, std::memory_order_release);
            }
        }

        bool allDry = true;
        int offset = 0;
        while (offset < frames) {
            int n = std::min(kChunkFrames, frames - offset);
            for (int i = 0; i < n; ++i) {
                float l = std::clamp(left[offset + i], -1.0f, 1.0f);
                float r = std::clamp(right[offset + i], -1.0f, 1.0f);
                inInterleaved[static_cast<size_t>(i * 2)] = static_cast<int16_t>(l * 32767.0f);
                inInterleaved[static_cast<size_t>(i * 2 + 1)] = static_cast<int16_t>(r * 32767.0f);
            }

            bool dryPass = engine->process(inInterleaved.data(), outInterleaved.data(), n);
            if (!dryPass) {
                allDry = false;
                for (int i = 0; i < n; ++i) {
                    left[offset + i] = static_cast<float>(outInterleaved[static_cast<size_t>(i * 2)]) / 32768.0f;
                    right[offset + i] = static_cast<float>(outInterleaved[static_cast<size_t>(i * 2 + 1)]) / 32768.0f;
                }
            }
            offset += n;
        }

        float rawLevels[MOCHY_STAGE_LEVEL_COUNT] = {};
        engine->levels(rawLevels);
        for (int i = 0; i < MOCHY_STAGE_LEVEL_COUNT; ++i) {
            cachedLevels[static_cast<size_t>(i)].store(rawLevels[i], std::memory_order_relaxed);
        }
        return allDry;
    }

    void readLevels(float* out) const {
        for (int i = 0; i < MOCHY_STAGE_LEVEL_COUNT; ++i) {
            out[i] = cachedLevels[static_cast<size_t>(i)].load(std::memory_order_relaxed);
        }
    }
};

struct MochyFxProcessor {
    double fs;
    MochyFxParams params{};
    MochyFxParams stagedParams{};
    std::mutex stageMutex;
    std::atomic<bool> paramsDirty{false};
    std::atomic<bool> resetRequested{false};

    std::array<StereoBiquad, 10> eqBands{};
    StereoBiquad bassShelf{};
    StereoBiquad trebleShelf{};
    StereoBiquad hpf{};
    StereoBiquad lpf{};
    StereoBiquad bassCutLpf{};

    std::vector<float> echoBufL;
    std::vector<float> echoBufR;
    size_t echoPos = 0;

    std::vector<float> flangerBufL;
    std::vector<float> flangerBufR;
    size_t flangerPos = 0;
    double flangerPhase = 0.0;

    std::array<float, 2048> reverbL{};
    std::array<float, 2048> reverbR{};
    size_t reverbPos = 0;

    double orbitPhase = 0.0;
    double lufsEma = 0.0;
    std::atomic<float> atomicLufs{-70.0f};
    std::atomic<bool> atomicSilent{true};
    float crushHoldL = 0.0f;
    float crushHoldR = 0.0f;
    int crushCounter = 0;

    explicit MochyFxProcessor(double sampleRate)
        : fs(std::max(8000.0, sampleRate)),
          echoBufL(static_cast<size_t>(fs * 2.0), 0.0f),
          echoBufR(static_cast<size_t>(fs * 2.0), 0.0f),
          flangerBufL(std::max<size_t>(64, static_cast<size_t>(fs * 0.03)), 0.0f),
          flangerBufR(std::max<size_t>(64, static_cast<size_t>(fs * 0.03)), 0.0f) {
        params.enabled = true;
        params.crossmix_gain = 1.0f;
        params.high_cut_hz = 20000.0f;
        params.limiter_enabled = true;
        stagedParams = params;
        rebuildFilters();
    }

    void enqueueParams(const MochyFxParams& next) {
        {
            std::lock_guard<std::mutex> lock(stageMutex);
            stagedParams = next;
        }
        paramsDirty.store(true, std::memory_order_release);
    }

    void requestReset() {
        resetRequested.store(true, std::memory_order_release);
    }

    void clearStates() {
        for (auto& b : eqBands) b.resetState();
        bassShelf.resetState();
        trebleShelf.resetState();
        hpf.resetState();
        lpf.resetState();
        bassCutLpf.resetState();
        std::fill(echoBufL.begin(), echoBufL.end(), 0.0f);
        std::fill(echoBufR.begin(), echoBufR.end(), 0.0f);
        std::fill(flangerBufL.begin(), flangerBufL.end(), 0.0f);
        std::fill(flangerBufR.begin(), flangerBufR.end(), 0.0f);
        reverbL.fill(0.0f);
        reverbR.fill(0.0f);
        echoPos = 0;
        flangerPos = 0;
        reverbPos = 0;
        lufsEma = 0.0;
        atomicLufs.store(-70.0f, std::memory_order_relaxed);
        atomicSilent.store(true, std::memory_order_relaxed);
    }

    void rebuildFilters() {
        for (size_t i = 0; i < 10; ++i) {
            eqBands[i].setPeaking(fs, kEqFreqs[i], 1.41, params.eq_gains_db[i]);
        }
        bassShelf.setPeaking(fs, 85.0, 0.7, params.bass_boost_db);
        trebleShelf.setPeaking(fs, 9000.0, 0.7, params.treble_boost_db);
        if (params.low_cut_hz > 25.0f) {
            hpf.setHighPass(fs, params.low_cut_hz);
        }
        if (params.high_cut_hz > 40.0f && params.high_cut_hz < 19500.0f) {
            lpf.setLowPass(fs, params.high_cut_hz);
        }
        bassCutLpf.setLowPass(fs, 190.0);
    }

    void applyPendingOnAudioThread() {
        if (resetRequested.exchange(false, std::memory_order_acquire)) {
            clearStates();
        }
        if (paramsDirty.exchange(false, std::memory_order_acquire)) {
            std::unique_lock<std::mutex> lock(stageMutex, std::try_to_lock);
            if (lock.owns_lock()) {
                params = stagedParams;
                lock.unlock();
                rebuildFilters();
            } else {
                paramsDirty.store(true, std::memory_order_release);
            }
        }
    }

    void process(float* left, float* right, int frames) {
        if (!left || !right || frames <= 0) return;

        applyPendingOnAudioThread();

        double replayLinear = std::pow(10.0, params.replay_gain_db / 20.0);
        double deckGain = std::max(0.0f, params.crossmix_gain);
        bool useHpf = params.low_cut_hz > 25.0f;
        bool useLpf = params.high_cut_hz > 40.0f && params.high_cut_hz < 19500.0f;
        bool useFlanger = params.flanger_mix > 0.005f;

        size_t delaySamples = std::clamp(
            static_cast<size_t>((params.echo_delay_ms / 1000.0) * fs),
            size_t(1),
            echoBufL.size() - 1
        );

        double blockEnergy = 0.0;
        float maxSample = 0.0f;

        for (int i = 0; i < frames; ++i) {
            float l = left[i];
            float r = right[i];

            if (params.enabled) {
                for (size_t b = 0; b < 10; ++b) {
                    if (std::abs(params.eq_gains_db[b]) >= 0.05f) {
                        eqBands[b].process(l, r);
                    }
                }
                if (std::abs(params.bass_boost_db) >= 0.05f) {
                    bassShelf.process(l, r);
                }
                if (std::abs(params.treble_boost_db) >= 0.05f) {
                    trebleShelf.process(l, r);
                }

                // Bass cut (< 190Hz) for BassSwap transitions
                if (params.bass_cut > 0.01f) {
                    float lowL = l, lowR = r;
                    bassCutLpf.process(lowL, lowR);
                    l -= lowL * params.bass_cut;
                    r -= lowR * params.bass_cut;
                }

                if (useHpf) hpf.process(l, r);
                if (useLpf) lpf.process(l, r);

                // Mid/Side isolation
                if (params.vocal_center_cut > 0.01f || params.side_cut > 0.01f) {
                    float mid = (l + r) * 0.5f * (1.0f - params.vocal_center_cut);
                    float side = (l - r) * 0.5f * (1.0f - params.side_cut);
                    l = mid + side;
                    r = mid - side;
                }

                // Lo-Fi bit/sample crush
                if (params.crush_mix > 0.01f) {
                    int step = std::max(1, static_cast<int>(1 + params.crush_mix * 7));
                    if (crushCounter++ % step == 0) {
                        crushHoldL = std::round(l * 24.0f) / 24.0f;
                        crushHoldR = std::round(r * 24.0f) / 24.0f;
                    }
                    l = l * (1.0f - params.crush_mix) + crushHoldL * params.crush_mix;
                    r = r * (1.0f - params.crush_mix) + crushHoldR * params.crush_mix;
                }

                // Harmonic warmth soft saturation
                if (params.warmth > 0.01f) {
                    float drive = 1.0f + params.warmth * 1.8f;
                    l = l * (1.0f - params.warmth) + std::tanh(l * drive) * params.warmth;
                    r = r * (1.0f - params.warmth) + std::tanh(r * drive) * params.warmth;
                }

                // Modulated Stereo Flanger (used by Crossmix `.phaserGlide` and FX)
                if (useFlanger) {
                    flangerPhase += (2.0 * kPi * 0.35) / fs;
                    if (flangerPhase > 2.0 * kPi) flangerPhase -= 2.0 * kPi;
                    double modL = 0.0015 + 0.0050 * (0.5 + 0.5 * std::sin(flangerPhase));
                    double modR = 0.0015 + 0.0050 * (0.5 + 0.5 * std::cos(flangerPhase));
                    size_t bufSize = flangerBufL.size();

                    auto readInterp = [bufSize](const std::vector<float>& buf, size_t writePos, double delaySmp) -> float {
                        double clamped = std::clamp(delaySmp, 1.0, static_cast<double>(bufSize - 2));
                        size_t d0 = static_cast<size_t>(clamped);
                        float frac = static_cast<float>(clamped - static_cast<double>(d0));
                        size_t idx0 = (writePos + bufSize - d0) % bufSize;
                        size_t idx1 = (idx0 + bufSize - 1) % bufSize;
                        return buf[idx0] * (1.0f - frac) + buf[idx1] * frac;
                    };

                    float fWetL = readInterp(flangerBufL, flangerPos, modL * fs);
                    float fWetR = readInterp(flangerBufR, flangerPos, modR * fs);
                    flangerBufL[flangerPos] = l + fWetL * 0.35f;
                    flangerBufR[flangerPos] = r + fWetR * 0.35f;
                    flangerPos = (flangerPos + 1) % bufSize;

                    float mix = std::clamp(params.flanger_mix, 0.0f, 1.0f);
                    l = l * (1.0f - mix * 0.45f) + fWetL * mix * 0.65f;
                    r = r * (1.0f - mix * 0.45f) + fWetR * mix * 0.65f;
                }

                // Ping-pong delay send
                size_t readPos = (echoPos + echoBufL.size() - delaySamples) % echoBufL.size();
                float wetL = echoBufR[readPos];
                float wetR = echoBufL[readPos];
                echoBufL[echoPos] = l + wetL * 0.42f;
                echoBufR[echoPos] = r + wetR * 0.42f;
                echoPos = (echoPos + 1) % echoBufL.size();
                if (params.echo_mix > 0.005f) {
                    l += wetL * params.echo_mix;
                    r += wetR * params.echo_mix;
                }

                // Lightweight stereo reverb
                if (params.reverb_mix > 0.005f) {
                    size_t tap1 = (reverbPos + reverbL.size() - 787) % reverbL.size();
                    size_t tap2 = (reverbPos + reverbR.size() - 1217) % reverbR.size();
                    float revL = (reverbL[tap1] + reverbR[tap2]) * 0.35f;
                    float revR = (reverbR[tap1] - reverbL[tap2]) * 0.35f;
                    reverbL[reverbPos] = l + revL * 0.55f;
                    reverbR[reverbPos] = r + revR * 0.55f;
                    reverbPos = (reverbPos + 1) % reverbL.size();
                    l = l * (1.0f - params.reverb_mix * 0.4f) + revL * params.reverb_mix;
                    r = r * (1.0f - params.reverb_mix * 0.4f) + revR * params.reverb_mix;
                }

                // 8D Audio Auto-Orbit Panning
                if (params.orbit_rate_hz > 0.001f) {
                    orbitPhase += (2.0 * kPi * params.orbit_rate_hz) / fs;
                    if (orbitPhase > 2.0 * kPi) orbitPhase -= 2.0 * kPi;
                    float pan = static_cast<float>(std::sin(orbitPhase)) * 0.45f;
                    float mono = (l + r) * 0.5f;
                    l = l * 0.5f + mono * (0.5f - pan);
                    r = r * 0.5f + mono * (0.5f + pan);
                }
            }

            float scale = static_cast<float>(replayLinear * deckGain);
            l *= scale;
            r *= scale;

            if (params.limiter_enabled) {
                l = std::tanh(l);
                r = std::tanh(r);
            }

            // Guard against NaN/Inf propagation on malformed input buffers.
            if (!std::isfinite(l)) l = 0.0f;
            if (!std::isfinite(r)) r = 0.0f;

            left[i] = l;
            right[i] = r;

            double sq = 0.5 * (static_cast<double>(l) * l + static_cast<double>(r) * r);
            blockEnergy += sq;
            maxSample = std::max(maxSample, std::max(std::abs(l), std::abs(r)));
        }

        double meanSq = blockEnergy / frames;
        lufsEma = lufsEma * 0.85 + meanSq * 0.15;
        float computedLufs = (lufsEma <= 1e-9) ? -70.0f : static_cast<float>(10.0 * std::log10(lufsEma) - 0.691);
        atomicLufs.store(computedLufs, std::memory_order_relaxed);
        atomicSilent.store(maxSample < 1e-4f, std::memory_order_relaxed);
    }
};

} // namespace

extern "C" {

bool mochy_stage_load_hrtf(const uint8_t* data, size_t size) {
    if (!data || size == 0) return false;
    return stage::loadHrtf(data, size);
}

void* mochy_stage_create(int sample_rate, int channels) {
    return new MochyStageWrapper(sample_rate, channels);
}

void mochy_stage_destroy(void* engine) {
    delete static_cast<MochyStageWrapper*>(engine);
}

void mochy_stage_set_params(void* engine, const float* params, int count) {
    if (!engine || !params || count <= 0) return;
    static_cast<MochyStageWrapper*>(engine)->enqueueParams(params, count);
}

void mochy_stage_clear(void* engine) {
    if (!engine) return;
    static_cast<MochyStageWrapper*>(engine)->requestClear();
}

bool mochy_stage_process_f32(void* engine, float* left, float* right, int frames) {
    if (!engine || !left || !right || frames <= 0) return true;
    return static_cast<MochyStageWrapper*>(engine)->processF32(left, right, frames);
}

void mochy_stage_levels(void* engine, float* out_levels_6) {
    if (!engine || !out_levels_6) return;
    static_cast<MochyStageWrapper*>(engine)->readLevels(out_levels_6);
}

void* mochy_fx_create(double sample_rate) {
    return new MochyFxProcessor(sample_rate);
}

void mochy_fx_destroy(void* fx) {
    delete static_cast<MochyFxProcessor*>(fx);
}

void mochy_fx_update(void* fx, const MochyFxParams* params) {
    if (!fx || !params) return;
    static_cast<MochyFxProcessor*>(fx)->enqueueParams(*params);
}

void mochy_fx_reset(void* fx) {
    if (!fx) return;
    static_cast<MochyFxProcessor*>(fx)->requestReset();
}

void mochy_fx_process(void* fx, float* left, float* right, int frames) {
    if (!fx) return;
    static_cast<MochyFxProcessor*>(fx)->process(left, right, frames);
}

float mochy_fx_get_lufs(void* fx) {
    if (!fx) return -70.0f;
    return static_cast<MochyFxProcessor*>(fx)->atomicLufs.load(std::memory_order_relaxed);
}

bool mochy_fx_is_silent(void* fx) {
    if (!fx) return true;
    return static_cast<MochyFxProcessor*>(fx)->atomicSilent.load(std::memory_order_relaxed);
}

} // extern "C"
