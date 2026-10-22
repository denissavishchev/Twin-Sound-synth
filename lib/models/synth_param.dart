import 'dart:math' as math;

enum ParamScale { linear, log, discrete }

/// Every knob of the synth. The enum order is the parameter id used by the
/// native engine (see `SP_*` in src/synth.h) — keep both in sync.
enum SynthParam {
  wave('wave', 'WAVE', 0, 2, 1, ParamScale.discrete),
  octave('oct', 'OCT', -2, 2, 0, ParamScale.discrete),
  tune('tune', 'DETUNE', -100, 100, 0, ParamScale.linear),
  cutoff('cutoff', 'CUTOFF', 80, 20000, 6000, ParamScale.log),
  resonance('res', 'RES', 0, 1, 0.15, ParamScale.linear),
  attack('attack', 'ATTACK', 0.002, 3, 0.006, ParamScale.log),
  decay('decay', 'DECAY', 0.01, 3, 0.3, ParamScale.log),
  sustain('sustain', 'SUSTAIN', 0, 1, 0.8, ParamScale.linear),
  release('release', 'RELEASE', 0.02, 5, 0.25, ParamScale.log),
  lfoWave('lfoWave', 'LFO WAVE', 0, 2, 0, ParamScale.discrete),
  lfoRate('lfoRate', 'LFO\nRATE', 0.1, 20, 4, ParamScale.log),
  lfoDepth('lfoDepth', 'LFO\nDEPTH', 0, 1, 0.0, ParamScale.linear),
  lfoDest('lfoDest', 'LFO\nDEST', 0, 2, 0, ParamScale.discrete),
  reverbSize('revSize', 'REV·SIZE', 0, 1, 0.5, ParamScale.linear),
  reverbMix('revMix', 'REVERB', 0, 1, 0, ParamScale.linear),
  chorusDepth('choDepth', 'CHO·DEPTH', 0, 1, 0, ParamScale.linear),
  chorusRate('choRate', 'CHO·RATE', 0.1, 5, 0.8, ParamScale.log),
  delayTime('dlyTime', 'DELAY\nTIME', 0.03, 1.2, 0.35, ParamScale.log),
  delayFeedback('dlyFb', 'DLY·FB', 0, 0.95, 0.35, ParamScale.linear),
  delayMix('dlyMix', 'DELAY\nMIX', 0, 1, 0, ParamScale.linear),
  volume('volume', 'VOL', 0, 1, 0.8, ParamScale.linear);

  const SynthParam(this.key, this.label, this.min, this.max, this.def, this.scale);

  /// JSON key.
  final String key;
  final String label;
  final double min, max, def;
  final ParamScale scale;

  int get id => index;

  double clamp(double v) {
    final c = v.clamp(min, max).toDouble();
    return scale == ParamScale.discrete ? c.roundToDouble() : c;
  }

  /// Real value → knob position 0..1.
  double toNorm(double v) {
    v = v.clamp(min, max).toDouble();
    return scale == ParamScale.log
        ? math.log(v / min) / math.log(max / min)
        : (v - min) / (max - min);
  }

  /// Knob position 0..1 → real value.
  double fromNorm(double n) {
    n = n.clamp(0.0, 1.0).toDouble();
    final v = scale == ParamScale.log
        ? min * math.pow(max / min, n)
        : min + n * (max - min);
    return clamp(v.toDouble());
  }

  /// Text for the value read-out above a slider.
  String format(double v) {
    switch (this) {
      case SynthParam.wave:
        return const ['SINE', 'SQUARE', 'TRI'][v.round().clamp(0, 2)];
      case SynthParam.lfoDest:
        return const ['PITCH', 'FILTER', 'VOL'][v.round().clamp(0, 2)];
      case SynthParam.octave:
        return v > 0 ? '+${v.round()} OCT' : '${v.round()} OCT';
      case SynthParam.tune:
        return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)} ct';
      case SynthParam.cutoff:
      case SynthParam.lfoRate:
      case SynthParam.chorusRate:
        return v >= 1000
            ? '${(v / 1000).toStringAsFixed(1)} kHz'
            : '${v.toStringAsFixed(v < 10 ? 1 : 0)} Hz';
      case SynthParam.attack:
      case SynthParam.decay:
      case SynthParam.release:
      case SynthParam.delayTime:
        return v < 1 ? '${(v * 1000).round()} ms' : '${v.toStringAsFixed(2)} s';
      default:
        return '${(toNorm(v) * 100).round()}%';
    }
  }
}
