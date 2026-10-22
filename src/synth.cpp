#include "synth.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <vector>

#include "miniaudio.h"

#if defined(__ANDROID__)
#include <android/log.h>
#define SLOG(...) __android_log_print(ANDROID_LOG_INFO, "synth", __VA_ARGS__)
#else
#define SLOG(...) ((void)0)
#endif

namespace {

constexpr int kMaxVoices = 16;
constexpr int kEventCap = 512;  // power of two
constexpr int kScopeLen = 4096;
constexpr float kPi = 3.14159265358979f;
constexpr float kTwoPi = 6.28318530717959f;

// Defaults mirror lib/models/synth_param.dart (Dart overwrites them at start).
const float kDefaults[SP_COUNT] = {
    0.f,    // WAVE
    0.f,    // OCT
    0.f,    // TUNE
    6000.f, // CUTOFF
    0.15f,  // RES
    0.01f,  // ATTACK
    0.3f,   // DECAY
    0.7f,   // SUSTAIN
    0.3f,   // RELEASE
    0.f,    // LFO_WAVE
    4.f,    // LFO_RATE
    0.f,    // LFO_DEPTH
    0.f,    // LFO_DEST
    0.5f,   // REV_SIZE
    0.f,    // REV_MIX
    0.f,    // CHO_DEPTH
    0.8f,   // CHO_RATE
    0.35f,  // DLY_TIME
    0.35f,  // DLY_FB
    0.f,    // DLY_MIX
    0.8f,   // VOLUME
};

inline float clampf(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// Two-sample polynomial band-limited step: removes the aliasing of the
// square wave's discontinuities.
inline float polyBlep(float t, float dt) {
  if (t < dt) {
    t /= dt;
    return t + t - t * t - 1.f;
  }
  if (t > 1.f - dt) {
    t = (t - 1.f) / dt;
    return t * t + t + t + 1.f;
  }
  return 0.f;
}

// Presence for the pure shapes. A sine has no content above its fundamental and
// a triangle very little, which sounds dull/muffled next to a square (especially
// on low notes). This adds a few quiet saw-like partials (2..7, amplitude 1/k)
// to them. Partials are generated with a Chebyshev recurrence (one sin + one cos
// per sample) and only up to ~0.45 * sample rate so they never alias.
constexpr float kAir = 0.40f;

inline float airPartials(float theta, float sine, float dt) {
  const int kmax = std::min(7, (int)(0.45f / std::max(dt, 1e-4f)));
  if (kmax < 2) return 0.f;
  const float c1 = std::cos(theta);
  float prev = 0.f, cur = sine, sum = 0.f;
  for (int k = 2; k <= kmax; k++) {
    const float next = 2.f * c1 * cur - prev;  // sin(k * theta)
    sum += next / (float)k;
    prev = cur;
    cur = next;
  }
  return sum;
}

// Waveform morph: 0 = sine, 1 = square, 2 = triangle.
inline float oscSample(float phase, float dt, float morph) {
  const float theta = kTwoPi * phase;
  const float sine = std::sin(theta);
  float out;
  if (morph <= 0.0001f) {
    out = sine;
  } else {
    float sq = phase < 0.5f ? 1.f : -1.f;
    sq += polyBlep(phase, dt);
    float p2 = phase + 0.5f;
    if (p2 >= 1.f) p2 -= 1.f;
    sq -= polyBlep(p2, dt);
    if (morph <= 1.f) {
      out = sine + (sq - sine) * morph;
    } else {
      const float tri = 4.f * std::fabs(phase - 0.5f) - 1.f;
      out = sq + (tri - sq) * (morph - 1.f);
    }
  }
  // 1 at a pure sine / triangle, 0 at the (already bright) square
  const float pure = morph <= 1.f ? 1.f - morph : morph - 1.f;
  if (pure > 0.001f) out += kAir * pure * airPartials(theta, sine, dt);
  return out;
}

// Plain (non band-limited) shapes are fine for a sub-audio LFO.
inline float lfoSample(float phase, float morph) {
  const float sine = std::sin(kTwoPi * phase);
  const float sq = phase < 0.5f ? 1.f : -1.f;
  const float tri = 4.f * std::fabs(phase - 0.5f) - 1.f;
  if (morph <= 1.f) return sine + (sq - sine) * morph;
  return sq + (tri - sq) * (morph - 1.f);
}

// `key` identifies a held key: low 7 bits = MIDI pitch, upper bits = the
// keyboard (zone) it came from, so two keyboards can hold the same pitch
// independently.
struct Event {
  uint8_t type;  // 0 off, 1 on, 2 all off
  int16_t key;
  float vel;
};

enum Stage : uint8_t { kIdle, kAttack, kDecay, kSustain, kRelease };

struct Voice {
  bool active = false;
  bool gate = false;
  int note = 0;
  float vel = 0;
  float phase = 0;
  float env = 0;
  Stage stage = kIdle;
  uint64_t age = 0;
  float ic1 = 0, ic2 = 0;  // state-variable filter memory
};

// ---------------------------------------------------------------- effects

struct DelayLine {
  std::vector<float> buf;
  int pos = 0;
  void init(int n) {
    buf.assign(n, 0.f);
    pos = 0;
  }
  void write(float v) {
    buf[pos] = v;
    if (++pos >= (int)buf.size()) pos = 0;
  }
  // Fractional read, `d` samples behind the write head.
  float read(float d) const {
    const int n = (int)buf.size();
    float r = (float)pos - d;
    while (r < 0) r += n;
    const int i0 = (int)r;
    const float f = r - i0;
    const int i1 = i0 + 1 >= n ? 0 : i0 + 1;
    return buf[i0] * (1.f - f) + buf[i1] * f;
  }
};

struct Comb {
  std::vector<float> buf;
  int pos = 0;
  float store = 0;
  void init(int n) {
    buf.assign(n, 0.f);
    pos = 0;
    store = 0;
  }
  float process(float in, float feedback, float damp) {
    const float out = buf[pos];
    store = out * (1.f - damp) + store * damp;
    buf[pos] = in + store * feedback;
    if (++pos >= (int)buf.size()) pos = 0;
    return out;
  }
};

struct Allpass {
  std::vector<float> buf;
  int pos = 0;
  void init(int n) {
    buf.assign(n, 0.f);
    pos = 0;
  }
  float process(float in) {
    const float b = buf[pos];
    const float out = b - in;
    buf[pos] = in + b * 0.5f;
    if (++pos >= (int)buf.size()) pos = 0;
    return out;
  }
};

// ----------------------------------------------------------------- engine

// One complete synth voice-bank + filter + LFO + effects chain. The engine owns
// two of them (one per keyboard), each with its own parameters.
struct Part {
  float sr = 48000.f;
  std::atomic<float> target[SP_COUNT];
  float cur[SP_COUNT];
  float smoothCoef = 0.01f;

  Voice voices[kMaxVoices];
  uint64_t ageCounter = 0;

  // global modulation state
  float lfoPhase = 0, lfoOut = 0;
  float wPitch = 0, wFilter = 0, wVol = 0;  // smoothed destination amounts

  // effects
  DelayLine choL, choR;
  float choPhase = 0;
  DelayLine dlyL, dlyR;
  float dlyFbL = 0, dlyFbR = 0, dlyTime = 0;
  static constexpr int kCombs = 8, kAll = 4;
  Comb combL[kCombs], combR[kCombs];
  Allpass apL[kAll], apR[kAll];
  float denorm = 1e-18f;

  std::atomic<float> peak{0};
  std::atomic<int> activeVoices{0};

  Part() {
    for (int i = 0; i < SP_COUNT; i++) {
      target[i].store(kDefaults[i]);
      cur[i] = kDefaults[i];
    }
  }

  void init(float sampleRate) {
    sr = sampleRate;
    smoothCoef = 1.f - std::exp(-1.f / (0.006f * sr));  // ~6 ms glide
    const float k = sr / 44100.f;
    choL.init((int)(0.06f * sr));
    choR.init((int)(0.06f * sr));
    dlyL.init((int)(2.2f * sr));
    dlyR.init((int)(2.2f * sr));
    static const int combT[kCombs] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
    static const int apT[kAll] = {556, 441, 341, 225};
    for (int i = 0; i < kCombs; i++) {
      combL[i].init((int)(combT[i] * k));
      combR[i].init((int)((combT[i] + 23) * k));
    }
    for (int i = 0; i < kAll; i++) {
      apL[i].init((int)(apT[i] * k));
      apR[i].init((int)((apT[i] + 23) * k));
    }
    dlyTime = kDefaults[SP_DLY_TIME] * sr;
  }

  void allOff() {
    for (auto& v : voices)
      if (v.active) release(v);
  }

  void release(Voice& v) {
    v.gate = false;
    v.stage = kRelease;
  }

  void noteOn(int note, float vel) {
    Voice* v = nullptr;
    for (auto& c : voices)  // re-trigger the same key on its own voice
      if (c.active && c.note == note) {
        v = &c;
        break;
      }
    if (!v)
      for (auto& c : voices)
        if (!c.active) {
          v = &c;
          break;
        }
    if (!v) {  // steal: quietest releasing voice, else the oldest
      float best = 1e9f;
      for (auto& c : voices)
        if (c.stage == kRelease && c.env < best) {
          best = c.env;
          v = &c;
        }
      if (!v) {
        uint64_t oldest = ~0ull;
        for (auto& c : voices)
          if (c.age < oldest) {
            oldest = c.age;
            v = &c;
          }
      }
    }
    const bool fresh = !(v->active && v->note == note);
    v->active = true;
    v->gate = true;
    v->note = note;
    v->vel = clampf(vel, 0.f, 1.f);
    v->stage = kAttack;
    v->age = ++ageCounter;
    if (fresh) {
      v->phase = 0;
      v->env = 0;
      v->ic1 = v->ic2 = 0;
    }
  }

  void noteOff(int note) {
    for (auto& v : voices)
      if (v.active && v.gate && v.note == note) release(v);
  }

  // -------- audio
  // Renders `frames` stereo frames (interleaved), overwriting `out`.
  void process(float* out, int frames) {
    float blockPeak = 0;

    for (int n = 0; n < frames; n++) {
      float* c = cur;
      for (int i = 0; i < SP_COUNT; i++) {
        const float t = target[i].load(std::memory_order_relaxed);
        c[i] += (t - c[i]) * smoothCoef;
      }
      const int dest = (int)(target[SP_LFO_DEST].load(std::memory_order_relaxed) + 0.5f);
      const float depth = c[SP_LFO_DEPTH];
      wPitch += ((dest == 0 ? depth : 0.f) - wPitch) * smoothCoef;
      wFilter += ((dest == 1 ? depth : 0.f) - wFilter) * smoothCoef;
      wVol += ((dest == 2 ? depth : 0.f) - wVol) * smoothCoef;

      // LFO (output slewed by ~1 ms so a square LFO doesn't click)
      lfoPhase += c[SP_LFO_RATE] / sr;
      if (lfoPhase >= 1.f) lfoPhase -= 1.f;
      lfoOut += (lfoSample(lfoPhase, c[SP_LFO_WAVE]) - lfoOut) * 0.03f;

      const float pitchMul =
          std::exp2(c[SP_OCT] + c[SP_TUNE] / 1200.f + lfoOut * wPitch * (2.f / 12.f));
      const float volMul = 1.f - wVol * 0.5f * (1.f + lfoOut);

      // Filter coefficients are shared by every voice (global cutoff).
      float fc = c[SP_CUTOFF] * std::exp2(lfoOut * wFilter * 3.f);
      fc = clampf(fc, 20.f, std::min(20000.f, sr * 0.45f));
      const float g = std::tan(kPi * fc / sr);
      const float k = 2.f - 1.92f * clampf(c[SP_RES], 0.f, 1.f);
      const float a1 = 1.f / (1.f + g * (g + k));
      const float a2 = g * a1;
      const float a3 = g * a2;

      const float atk = 1.f / (std::max(0.001f, c[SP_ATTACK]) * sr);
      const float decC = std::exp(-4.6f / (std::max(0.005f, c[SP_DECAY]) * sr));
      const float relC = std::exp(-6.9f / (std::max(0.01f, c[SP_RELEASE]) * sr));
      const float sus = clampf(c[SP_SUSTAIN], 0.f, 1.f);
      const float morph = clampf(c[SP_WAVE], 0.f, 2.f);
      // Perceived-loudness match. Equal RMS is not equal loudness: a square's many
      // harmonics sit where the ear is most sensitive, so it sounds roughly 6 dB
      // louder than a sine of the same RMS (even on headphones). The pure shapes
      // are therefore kept at full level and the square is turned down by ~8 dB
      // (sine 1.0 -> square 0.27 -> triangle 1.0). Turning the sine up instead
      // would push it into the soft clipper and make all shapes sound alike.
      const float waveGain = morph <= 1.f ? 1.0f + (0.27f - 1.0f) * morph
                                          : 0.27f + (1.0f - 0.27f) * (morph - 1.f);

      float mix = 0.f;
      for (auto& v : voices) {
        if (!v.active) continue;
        switch (v.stage) {
          case kAttack:
            v.env += atk;
            if (v.env >= 1.f) {
              v.env = 1.f;
              v.stage = kDecay;
            }
            break;
          case kDecay:
            v.env = sus + (v.env - sus) * decC;
            if (v.env - sus < 1e-4f) {
              v.env = sus;
              v.stage = kSustain;
            }
            break;
          case kSustain:
            v.env = sus;
            break;
          case kRelease:
            v.env *= relC;
            if (v.env < 1e-4f) {
              v.active = false;
              v.stage = kIdle;
              continue;
            }
            break;
          default:
            break;
        }
        const float freq = 440.f * std::exp2(((v.note & 127) - 69) / 12.f) * pitchMul;
        const float dt = clampf(freq / sr, 0.f, 0.45f);
        v.phase += dt;
        if (v.phase >= 1.f) v.phase -= 1.f;
        float s = oscSample(v.phase, dt, morph);

        // TPT state-variable low-pass
        const float v3 = s - v.ic2;
        const float v1 = a1 * v.ic1 + a2 * v3;
        const float v2 = v.ic2 + a2 * v.ic1 + a3 * v3;
        v.ic1 = 2.f * v1 - v.ic1;
        v.ic2 = 2.f * v2 - v.ic2;
        mix += v2 * v.env * (0.35f + 0.65f * v.vel) * waveGain;
      }
      float dry = mix * 0.32f * volMul;

      // ---- chorus (two LFO-modulated taps, 90° apart → stereo)
      float l = dry, r = dry;
      const float chD = c[SP_CHO_DEPTH];
      choPhase += c[SP_CHO_RATE] / sr;
      if (choPhase >= 1.f) choPhase -= 1.f;
      choL.write(dry);
      choR.write(dry);
      if (chD > 0.001f) {
        const float base = 0.012f * sr, span = (0.001f + 0.005f * chD) * sr;
        const float tl = choL.read(base + span * std::sin(kTwoPi * choPhase));
        const float tr = choR.read(base + span * std::sin(kTwoPi * (choPhase + 0.25f)));
        const float w = 0.5f * chD;
        l = dry * (1.f - 0.3f * w) + tl * w;
        r = dry * (1.f - 0.3f * w) + tr * w;
      }

      // ---- stereo ping-pong delay
      const float dMix = c[SP_DLY_MIX];
      dlyTime += (c[SP_DLY_TIME] * sr - dlyTime) * 0.0005f;  // slow glide = tape-like
      const float dl = dlyL.read(std::max(1.f, dlyTime));
      const float dr = dlyR.read(std::max(1.f, dlyTime));
      const float fb = clampf(c[SP_DLY_FB], 0.f, 0.95f);
      dlyFbL += (dr - dlyFbL) * 0.4f;  // darken each repeat
      dlyFbR += (dl - dlyFbR) * 0.4f;
      dlyL.write((l + r) * 0.5f + dlyFbL * fb);
      dlyR.write(dlyFbR * fb);
      l += dl * dMix;
      r += dr * dMix;

      // ---- reverb (Freeverb topology)
      const float rMix = c[SP_REV_MIX];
      {
        const float size = clampf(c[SP_REV_SIZE], 0.f, 1.f);
        const float fbk = 0.7f + 0.28f * size;
        const float in = (l + r) * 0.015f + denorm;
        denorm = -denorm;
        float wl = 0, wr = 0;
        for (int i = 0; i < kCombs; i++) {
          wl += combL[i].process(in, fbk, 0.35f);
          wr += combR[i].process(in, fbk, 0.35f);
        }
        for (int i = 0; i < kAll; i++) {
          wl = apL[i].process(wl);
          wr = apR[i].process(wr);
        }
        l = l * (1.f - 0.35f * rMix) + wl * 3.f * rMix;
        r = r * (1.f - 0.35f * rMix) + wr * 3.f * rMix;
      }

      // ---- master
      const float vol = clampf(c[SP_VOLUME], 0.f, 1.f);
      const float gain = vol * vol * 6.5f;
      l = std::tanh(l * gain);
      r = std::tanh(r * gain);
      out[2 * n] = l;
      out[2 * n + 1] = r;
      blockPeak = std::max(blockPeak, std::max(std::fabs(l), std::fabs(r)));
    }
    const float old = peak.load(std::memory_order_relaxed);
    peak.store(std::max(blockPeak, old * 0.9f), std::memory_order_relaxed);
    int active = 0;
    for (auto& v : voices) active += v.active ? 1 : 0;
    activeVoices.store(active, std::memory_order_relaxed);
  }
};

// Two independent parts mixed together, plus the lock-free event queue and the
// scope buffer. A key's zone (key >> 7) selects the part that plays it.
struct Engine {
  static constexpr int kParts = 2;
  float sr = 48000.f;
  Part parts[kParts];

  Event events[kEventCap];
  std::atomic<uint32_t> evHead{0};  // written by the producer (UI thread)
  std::atomic<uint32_t> evTail{0};  // written by the audio thread

  std::vector<float> tmp[kParts];
  float scope[kScopeLen] = {0};
  std::atomic<uint32_t> scopePos{0};

  static constexpr int kChunk = 1024;

  void init(float sampleRate) {
    sr = sampleRate;
    for (auto& p : parts) p.init(sampleRate);
    for (auto& t : tmp) t.assign(kChunk * 2, 0.f);
  }

  void push(uint8_t type, int key, float vel) {
    const uint32_t h = evHead.load(std::memory_order_relaxed);
    const uint32_t t = evTail.load(std::memory_order_acquire);
    if (h - t >= (uint32_t)kEventCap) return;  // queue full: drop
    events[h & (kEventCap - 1)] = {type, (int16_t)key, vel};
    evHead.store(h + 1, std::memory_order_release);
  }

  void drain() {
    uint32_t t = evTail.load(std::memory_order_relaxed);
    const uint32_t h = evHead.load(std::memory_order_acquire);
    while (t != h) {
      const Event& e = events[t & (kEventCap - 1)];
      const int zone = (e.key >> 7) & (kParts - 1);
      if (e.type == 1) parts[zone].noteOn(e.key, e.vel);
      else if (e.type == 0) parts[zone].noteOff(e.key);
      else
        for (auto& p : parts) p.allOff();
      t++;
    }
    evTail.store(t, std::memory_order_release);
  }

  void process(float* out, int frames) {
    drain();
    int done = 0;
    while (done < frames) {
      const int n = std::min(kChunk, frames - done);
      for (int p = 0; p < kParts; p++) parts[p].process(tmp[p].data(), n);
      for (int i = 0; i < n; i++) {
        // each part is already soft-limited; the sum gets a gentle limiter too
        const float l = std::tanh(0.85f * (tmp[0][2 * i] + tmp[1][2 * i]));
        const float r = std::tanh(0.85f * (tmp[0][2 * i + 1] + tmp[1][2 * i + 1]));
        out[2 * (done + i)] = l;
        out[2 * (done + i) + 1] = r;
        const uint32_t sp = scopePos.load(std::memory_order_relaxed);
        scope[sp & (kScopeLen - 1)] = 0.5f * (l + r);
        scopePos.store(sp + 1, std::memory_order_release);
      }
      done += n;
    }
  }
};

std::unique_ptr<Engine> g_engine;
ma_device g_device;
bool g_deviceOn = false;

void dataCallback(ma_device* dev, void* out, const void*, ma_uint32 frames) {
  auto* e = static_cast<Engine*>(dev->pUserData);
  e->process(static_cast<float*>(out), (int)frames);
}

}  // namespace

extern "C" {

SYNTH_API int32_t synth_start(void) {
  if (g_deviceOn) return 0;
  g_engine.reset(new Engine());

  ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
  cfg.playback.format = ma_format_f32;
  cfg.playback.channels = 2;
  cfg.sampleRate = 0;  // the device's native rate: no resampling latency
  cfg.periodSizeInFrames = 256;
  cfg.periods = 2;
  cfg.performanceProfile = ma_performance_profile_low_latency;
  cfg.noPreSilencedOutputBuffer = MA_TRUE;
  cfg.dataCallback = dataCallback;
  cfg.pUserData = g_engine.get();

  const ma_result initRes = ma_device_init(nullptr, &cfg, &g_device);
  if (initRes != MA_SUCCESS) {
    SLOG("ma_device_init failed: %d (%s)", (int)initRes, ma_result_description(initRes));
    g_engine.reset();
    return -1;
  }
  SLOG("device ok: backend=%s rate=%u channels=%u period=%u", ma_get_backend_name(g_device.pContext->backend), g_device.sampleRate, g_device.playback.channels, g_device.playback.internalPeriodSizeInFrames);
  g_engine->init((float)g_device.sampleRate);
  const ma_result startRes = ma_device_start(&g_device);
  SLOG("device start: %d", (int)startRes);
  if (startRes != MA_SUCCESS) {
    ma_device_uninit(&g_device);
    g_engine.reset();
    return -2;
  }
  g_deviceOn = true;
  return 0;
}

SYNTH_API void synth_stop(void) {
  if (g_deviceOn) {
    ma_device_uninit(&g_device);
    g_deviceOn = false;
  }
}

SYNTH_API int32_t synth_init_offline(int32_t sample_rate) {
  g_engine.reset(new Engine());
  g_engine->init((float)sample_rate);
  return 0;
}

SYNTH_API void synth_render(float* interleaved, int32_t frames) {
  if (g_engine && !g_deviceOn) g_engine->process(interleaved, frames);
}

SYNTH_API void synth_destroy(void) {
  synth_stop();
  g_engine.reset();
}

SYNTH_API void synth_note_on(int32_t note, float velocity) {
  if (g_engine) g_engine->push(1, note, velocity);
}
SYNTH_API void synth_note_off(int32_t note) {
  if (g_engine) g_engine->push(0, note, 0);
}
SYNTH_API void synth_all_notes_off(void) {
  if (g_engine) g_engine->push(2, 0, 0);
}
SYNTH_API void synth_set_param(int32_t zone, int32_t id, float value) {
  if (g_engine && zone >= 0 && zone < Engine::kParts && id >= 0 && id < SP_COUNT)
    g_engine->parts[zone].target[id].store(value);
}
SYNTH_API float synth_get_peak(int32_t zone) {
  return (g_engine && zone >= 0 && zone < Engine::kParts) ? g_engine->parts[zone].peak.load() : 0.f;
}
SYNTH_API int32_t synth_active_voices(void) {
  if (!g_engine) return 0;
  int n = 0;
  for (auto& p : g_engine->parts) n += p.activeVoices.load();
  return n;
}
SYNTH_API int32_t synth_sample_rate(void) {
  return g_engine ? (int32_t)g_engine->sr : 0;
}
SYNTH_API void synth_get_scope(float* out, int32_t n) {
  if (!g_engine) {
    std::memset(out, 0, sizeof(float) * n);
    return;
  }
  n = std::min<int32_t>(n, kScopeLen);
  const uint32_t end = g_engine->scopePos.load(std::memory_order_acquire);
  for (int32_t i = 0; i < n; i++)
    out[i] = g_engine->scope[(end - n + i) & (kScopeLen - 1)];
}

}  // extern "C"
