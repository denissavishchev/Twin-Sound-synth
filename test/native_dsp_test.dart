import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_polyphonic_synth/core/audio/synth_bindings.dart' as n;
import 'package:ai_polyphonic_synth/models/synth_param.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

const sr = 48000;

Float32List render(int frames) {
  final p = calloc<Float>(frames * 2);
  n.synthRender(p, frames);
  final out = Float32List.fromList(p.asTypedList(frames * 2));
  calloc.free(p);
  return out;
}

double rms(Float32List b, [int from = 0, int? to]) {
  var s = 0.0;
  final end = to ?? b.length;
  for (var i = from; i < end; i++) {
    s += b[i] * b[i];
  }
  return math.sqrt(s / (end - from));
}

/// Frequency from rising zero crossings of the left channel.
double freqOf(Float32List b) {
  var first = -1, last = -1, count = 0;
  for (var i = 2; i < b.length ~/ 2 - 2; i++) {
    final a = b[(i - 1) * 2], c = b[i * 2];
    if (a < 0 && c >= 0) {
      if (first < 0) first = i;
      last = i;
      count++;
    }
  }
  return (count - 1) * sr / (last - first);
}

void main() {
  zoneTests();
  waveTests();
  setUp(() {
    n.synthInitOffline(sr);
    for (final p in SynthParam.values) {
      n.synthSetParam(0, p.id, p.def);
      n.synthSetParam(1, p.id, p.def);
    }
    n.synthSetParam(0, SynthParam.cutoff.id, 20000);
    n.synthSetParam(0, SynthParam.attack.id, 0.002);
  });
  tearDown(n.synthDestroy);

  test('silent until a note is played, then A4 sounds at 440 Hz', () {
    expect(rms(render(4800)), 0);
    n.synthNoteOn(69, 1);
    render(4800); // let envelope + smoothing settle
    final b = render(sr);
    expect(rms(b), greaterThan(0.01));
    expect(freqOf(b), closeTo(440, 3));
    expect(n.synthActiveVoices(), 1);
    expect(b.every((v) => v.isFinite && v.abs() <= 1.0), true);
  });

  test('octave knob transposes, polyphony sums, release ends the voice', () {
    n.synthSetParam(0, SynthParam.octave.id, 1);
    n.synthNoteOn(69, 1);
    render(sr ~/ 2);
    expect(freqOf(render(sr)), closeTo(880, 6));

    n.synthSetParam(0, SynthParam.octave.id, 0);
    n.synthNoteOn(60, 1);
    n.synthNoteOn(64, 1);
    n.synthNoteOn(67, 1);
    render(2400);
    expect(n.synthActiveVoices(), 4);

    n.synthAllNotesOff();
    n.synthSetParam(0, SynthParam.release.id, 0.05);
    render(sr * 2);
    expect(n.synthActiveVoices(), 0);
    final tail = render(2400);
    expect(rms(tail), lessThan(1e-3));
  });

  test('zones: same pitch on two keyboards is two voices, independent release', () {
    n.synthNoteOn(69, 1); // zone 0
    n.synthNoteOn(128 + 69, 1); // zone 1, same pitch
    render(4800);
    expect(n.synthActiveVoices(), 2);
    n.synthSetParam(0, SynthParam.release.id, 0.02);
    n.synthNoteOff(69);
    render(sr);
    expect(n.synthActiveVoices(), 1); // the other half still sounds
    expect(rms(render(4800)), greaterThan(0.01));
    expect(freqOf(render(sr)), closeTo(440, 3)); // pitch ignores the zone bits
  });

  test('parameter changes are smoothed (no zipper/pop)', () {
    n.synthSetParam(0, SynthParam.wave.id, 0); // sine: no edges to confuse the step test
    n.synthNoteOn(57, 1);
    render(sr ~/ 2);
    final before = render(2400);
    n.synthSetParam(0, SynthParam.volume.id, 0.1); // big jump
    final after = render(2400);
    // Largest sample-to-sample step must stay small despite the jump.
    var maxStep = 0.0;
    for (var i = 2; i < after.length; i += 2) {
      maxStep = math.max(maxStep, (after[i] - after[i - 2]).abs());
    }
    expect(maxStep, lessThan(0.15));
    expect(rms(after, after.length ~/ 2), lessThan(rms(before)));
  });

  test('effects: reverb and delay leave a tail after note-off', () {
    n.synthSetParam(0, SynthParam.reverbMix.id, 0.6);
    n.synthSetParam(0, SynthParam.delayMix.id, 0.6);
    n.synthSetParam(0, SynthParam.release.id, 0.02);
    n.synthNoteOn(60, 1);
    render(sr ~/ 4);
    n.synthNoteOff(60);
    render(sr ~/ 10);
    final tail = render(sr ~/ 2);
    expect(rms(tail), greaterThan(0.001));
    expect(tail.every((v) => v.isFinite), true);
  });

  test('every waveform and LFO destination renders finite audio', () {
    for (final wave in [0.0, 1.0, 2.0]) {
      for (final dest in [0.0, 1.0, 2.0]) {
        n.synthSetParam(0, SynthParam.wave.id, wave);
        n.synthSetParam(0, SynthParam.lfoDest.id, dest);
        n.synthSetParam(0, SynthParam.lfoDepth.id, 1);
        n.synthSetParam(0, SynthParam.cutoff.id, 800);
        n.synthSetParam(0, SynthParam.resonance.id, 0.9);
        n.synthNoteOn(48, 1);
        final b = render(sr ~/ 4);
        expect(b.every((v) => v.isFinite && v.abs() <= 1.0), true, reason: '$wave/$dest');
        expect(rms(b), greaterThan(0.001));
        n.synthAllNotesOff();
        render(sr ~/ 4);
      }
    }
  });
}

void waveTests() {
  setUp(() {
    n.synthInitOffline(sr);
    for (final p in SynthParam.values) {
      n.synthSetParam(0, p.id, p.def);
    }
  });
  tearDown(n.synthDestroy);

  Float32List note(double wave) {
    n.synthSetParam(0, SynthParam.wave.id, wave);
    n.synthNoteOn(60, 1);
    render(sr ~/ 3); // settle the 6 ms parameter glide + envelope
    final b = render(sr ~/ 2);
    n.synthAllNotesOff();
    n.synthSetParam(0, SynthParam.release.id, 0.02);
    render(sr);
    return b;
  }

  double hf(Float32List b) {
    var s = 0.0;
    for (var i = 2; i < b.length; i += 2) {
      final d = b[i] - b[i - 2];
      s += d * d;
    }
    return s;
  }

  test('sine and triangle keep some highs (not muffled), square stays brighter', () {
    final sine = note(0), square = note(1), tri = note(2);
    double bright(Float32List b) => hf(b) / (rms(b) * rms(b) * b.length);
    // theory: a pure C4 sine gives (2*pi*f/sr)^2 / 2 with this metric (the buffer
    // is interleaved stereo, hence the /2)
    final pureSine = math.pow(2 * math.pi * 261.63 / sr, 2) / 2;
    expect(bright(sine), greaterThan(pureSine * 1.8)); // clearly more than a pure sine
    expect(bright(tri), greaterThan(pureSine * 1.5));
    expect(bright(square), greaterThan(bright(sine) * 2.0)); // square still the brightest
  });

  test('shapes are audibly different and about equally loud', () {
    final sine = note(0), square = note(1), tri = note(2);
    // timbre: square has far more harmonics than triangle, triangle more than sine
    // brightness = high-frequency energy relative to the overall level
    double bright(Float32List b) => hf(b) / (rms(b) * rms(b) * b.length);
    expect(bright(square), greaterThan(bright(tri) * 2.5));
    // a triangle is only slightly brighter than a sine (harmonics fall off as
    // 1/n²), but its waveform is different: crest factor √3 vs √2
    double crest(Float32List b) => b.fold(0.0, (m, v) => math.max(m, v.abs())) / rms(b);
    expect(crest(tri), greaterThan(crest(sine) * 1.1));
    // Loudness: equal RMS sounds louder for the harmonic-rich square, so the pure
    // shapes carry MORE RMS (about +5..7 dB) to *sound* equally loud.
    expect(rms(sine) / rms(square), inInclusiveRange(1.8, 2.8));
    expect(rms(tri) / rms(square), inInclusiveRange(1.5, 2.4));
    double peak(Float32List b) => b.fold(0.0, (m, v) => math.max(m, v.abs()));
    expect(peak(sine), lessThan(0.9)); // headroom: tanh barely engaged
  });
}

void zoneTests() {
  setUp(() {
    n.synthInitOffline(sr);
    for (final z in [0, 1]) {
      for (final p in SynthParam.values) {
        n.synthSetParam(z, p.id, p.def);
      }
      n.synthSetParam(z, SynthParam.cutoff.id, 20000);
    }
  });
  tearDown(n.synthDestroy);

  test('halves are independent synths: own volume, octave-free pitch, own peak', () {
    n.synthSetParam(1, SynthParam.volume.id, 0); // right half silent
    n.synthNoteOn(60, 1); // left
    n.synthNoteOn(128 + 72, 1); // right
    render(sr ~/ 2);
    for (var i = 0; i < 60; i++) {
      render(256); // the peak meter decays once per audio block
    }
    expect(n.synthGetPeak(0), greaterThan(0.05));
    expect(n.synthGetPeak(1), lessThan(0.001));
    expect(n.synthActiveVoices(), 2);

    // now silence the left half instead and open the right one
    n.synthSetParam(0, SynthParam.volume.id, 0);
    n.synthSetParam(1, SynthParam.volume.id, 0.8);
    render(sr ~/ 2);
    for (var i = 0; i < 120; i++) {
      render(256); // the peak meter decays once per audio block
    }
    expect(n.synthGetPeak(0), lessThan(0.001));
    expect(n.synthGetPeak(1), greaterThan(0.05));
  });

  test('each half has its own cutoff: dark left, bright right', () {
    n.synthSetParam(0, SynthParam.wave.id, 1);
    n.synthSetParam(1, SynthParam.wave.id, 1);
    n.synthSetParam(0, SynthParam.cutoff.id, 150); // very dark
    n.synthNoteOn(60, 1);
    render(sr ~/ 4);
    final dark = render(sr ~/ 2);
    n.synthAllNotesOff();
    render(sr);
    n.synthSetParam(0, SynthParam.volume.id, 0);
    n.synthNoteOn(128 + 60, 1);
    render(sr ~/ 4);
    final bright = render(sr ~/ 2);
    // a bright square wave has far more high-frequency energy than a 150 Hz-filtered one
    double hf(Float32List b) {
      var s = 0.0;
      for (var i = 2; i < b.length; i += 2) {
        final d = b[i] - b[i - 2];
        s += d * d;
      }
      return s;
    }

    expect(hf(bright), greaterThan(hf(dark) * 20));
  });
}
