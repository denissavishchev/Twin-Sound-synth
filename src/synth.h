// C API of the polyphonic synth engine (consumed from Dart through dart:ffi).
//
// Threading: every function may be called from the UI thread. Note events and
// parameter changes are handed to the audio thread through a lock-free queue /
// atomics; the audio thread never allocates, locks or calls into Dart.
#ifndef AI_SYNTH_H
#define AI_SYNTH_H

#include <stdint.h>

#if defined(_WIN32)
#define SYNTH_API __declspec(dllexport)
#else
#define SYNTH_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Parameter ids — must match lib/models/synth_param.dart.
enum {
  SP_WAVE = 0,   // 0 sine … 1 square … 2 triangle (continuous morph)
  SP_OCT,        // -2..2 (octaves)
  SP_TUNE,       // -100..100 cents
  SP_CUTOFF,     // Hz
  SP_RES,        // 0..1
  SP_ATTACK,     // s
  SP_DECAY,      // s
  SP_SUSTAIN,    // 0..1
  SP_RELEASE,    // s
  SP_LFO_WAVE,   // 0..2
  SP_LFO_RATE,   // Hz
  SP_LFO_DEPTH,  // 0..1
  SP_LFO_DEST,   // 0 pitch, 1 filter, 2 volume
  SP_REV_SIZE,   // 0..1
  SP_REV_MIX,    // 0..1
  SP_CHO_DEPTH,  // 0..1
  SP_CHO_RATE,   // Hz
  SP_DLY_TIME,   // s
  SP_DLY_FB,     // 0..0.95
  SP_DLY_MIX,    // 0..1
  SP_VOLUME,     // 0..1
  SP_COUNT
};

// Opens the default output device and starts rendering. Returns 0 on success.
SYNTH_API int32_t synth_start(void);
SYNTH_API void synth_stop(void);

// Engine without an audio device (tests / offline rendering).
SYNTH_API int32_t synth_init_offline(int32_t sample_rate);
// Renders `frames` stereo frames (interleaved float) when running offline.
SYNTH_API void synth_render(float* interleaved, int32_t frames);
SYNTH_API void synth_destroy(void);

// `key` = pitch (0..127) + 128 * zone. Notes are matched by the whole key.
SYNTH_API void synth_note_on(int32_t key, float velocity);
SYNTH_API void synth_note_off(int32_t key);
SYNTH_API void synth_all_notes_off(void);
// Parameters are per keyboard half: zone 0 (left) and zone 1 (right).
SYNTH_API void synth_set_param(int32_t zone, int32_t id, float value);

SYNTH_API float synth_get_peak(int32_t zone);
SYNTH_API int32_t synth_active_voices(void);  // both halves
SYNTH_API int32_t synth_sample_rate(void);
// Copies the most recent `n` mono output samples (n <= 2048).
SYNTH_API void synth_get_scope(float* out, int32_t n);

#ifdef __cplusplus
}
#endif
#endif
