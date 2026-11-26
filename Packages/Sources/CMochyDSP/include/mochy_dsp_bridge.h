#ifndef MOCHY_DSP_BRIDGE_H
#define MOCHY_DSP_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Stage 3D HRTF Engine (matches Mochy `stage/engine.h`)

enum {
    MOCHY_STAGE_PARAM_COUNT = 133,
    MOCHY_STAGE_LEVEL_COUNT = 6
};

bool mochy_stage_load_hrtf(const uint8_t* data, size_t size);
void* mochy_stage_create(int sample_rate, int channels);
void mochy_stage_destroy(void* engine);
void mochy_stage_set_params(void* engine, const float* params, int count);
void mochy_stage_clear(void* engine);
bool mochy_stage_process_f32(void* engine, float* left, float* right, int frames);
void mochy_stage_levels(void* engine, float* out_levels_6);

// MARK: - FX & Crossmix DSP Bus

typedef struct {
    bool enabled;
    float eq_gains_db[10];     // 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
    float bass_boost_db;       // 0..12
    float treble_boost_db;     // -6..12
    float warmth;              // 0..1 harmonic soft saturation
    float reverb_mix;          // 0..1
    float orbit_rate_hz;       // 0 = off, typical 0.1..0.4 Hz for 8D Audio
    float replay_gain_db;      // loudness normalization + preamp gain
    bool limiter_enabled;

    // Crossmix DJ parameters per deck
    float crossmix_gain;       // 0..1 linear deck gain
    float low_cut_hz;          // > 25 triggers HPF sweep
    float high_cut_hz;         // < 19500 triggers LPF sweep
    float bass_cut;            // 0..1 attenuates < 190Hz
    float vocal_center_cut;    // 0..1 attenuates mid channel
    float side_cut;            // 0..1 attenuates side channel
    float echo_mix;            // 0..1 beat echo wet send
    float echo_delay_ms;       // delay time in ms
    float flanger_mix;         // 0..1 modulated stereo flanger
    float crush_mix;           // 0..1 lo-fi crush
} MochyFxParams;

void* mochy_fx_create(double sample_rate);
void mochy_fx_destroy(void* fx);
void mochy_fx_update(void* fx, const MochyFxParams* params);
void mochy_fx_reset(void* fx);
void mochy_fx_process(void* fx, float* left, float* right, int frames);
float mochy_fx_get_lufs(void* fx);
bool mochy_fx_is_silent(void* fx);

#ifdef __cplusplus
}
#endif

#endif
