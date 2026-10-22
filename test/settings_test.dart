import 'dart:io';

import 'package:ai_polyphonic_synth/core/audio/synth_engine.dart';
import 'package:ai_polyphonic_synth/models/synth_param.dart';
import 'package:ai_polyphonic_synth/services/settings_store.dart';
import 'package:ai_polyphonic_synth/state/synth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('synth_settings_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('sliders, wave switches and octaves survive an app restart', () async {
    final a = SynthState(NullSynthEngine(), SettingsStore(root: dir));
    await a.start();
    a.set(0, SynthParam.cutoff, 1234);
    a.set(0, SynthParam.wave, 2); // left: triangle
    a.set(1, SynthParam.wave, 0); // right: sine
    a.set(1, SynthParam.delayMix, 0.6);
    a.set(1, SynthParam.volume, 0.3);
    a.setOctave(0, -2);
    a.setOctave(1, 2);
    await a.flush();

    final engine = NullSynthEngine();
    final b = SynthState(engine, SettingsStore(root: dir)); // "next launch"
    await b.start();
    expect(b.value(0, SynthParam.cutoff), closeTo(1234, 0.5));
    expect(b.value(0, SynthParam.wave), 2);
    expect(b.value(1, SynthParam.wave), 0);
    expect(b.value(1, SynthParam.delayMix), closeTo(0.6, 1e-3));
    expect(b.value(1, SynthParam.volume), closeTo(0.3, 1e-3));
    expect(b.octave(0), -2);
    expect(b.octave(1), 2);
    // ... and the restored values are what the engine is told at start-up
    final sent = {for (final p in engine.params) (p.$1, p.$2): p.$3};
    expect(sent[(1, SynthParam.wave.id)], 0);
    expect(sent[(0, SynthParam.cutoff.id)], closeTo(1234, 0.5));
  });

  test('autosave fires shortly after a change (no explicit flush)', () async {
    final a = SynthState(NullSynthEngine(), SettingsStore(root: dir));
    await a.start();
    a.set(0, SynthParam.lfoDepth, 0.5);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final b = SynthState(NullSynthEngine(), SettingsStore(root: dir));
    await b.start();
    expect(b.value(0, SynthParam.lfoDepth), closeTo(0.5, 1e-3));
  });

  test('missing or corrupt file falls back to the defaults', () async {
    File('${dir.path}/twin_sound_settings.json').writeAsStringSync('{ not json');
    final s = SynthState(NullSynthEngine(), SettingsStore(root: dir));
    await s.start();
    expect(s.value(0, SynthParam.cutoff), SynthParam.cutoff.def);
    expect(s.octave(1), 1);
    // a valid file with partial / odd content is tolerated too
    File('${dir.path}/twin_sound_settings.json')
        .writeAsStringSync('{"zones":[{"params":{"cutoff":500}}],"octaves":[9]}');
    final t = SynthState(NullSynthEngine(), SettingsStore(root: dir));
    await t.start();
    expect(t.value(0, SynthParam.cutoff), 500);
    expect(t.value(1, SynthParam.cutoff), SynthParam.cutoff.def);
    expect(t.octave(0), 2); // clamped
  });
}
