import 'package:ai_polyphonic_synth/app.dart';
import 'package:ai_polyphonic_synth/core/audio/synth_engine.dart';
import 'package:ai_polyphonic_synth/models/patch_config.dart';
import 'package:ai_polyphonic_synth/models/synth_param.dart';
import 'package:ai_polyphonic_synth/services/settings_store.dart';
import 'package:ai_polyphonic_synth/state/synth_state.dart';
import 'package:ai_polyphonic_synth/ui/widgets/control_panel.dart';
import 'package:ai_polyphonic_synth/ui/widgets/keyboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<NullSynthEngine> pump(WidgetTester t, {Size size = const Size(844, 390)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final engine = NullSynthEngine();
  await t.pumpWidget(SynthApp(engine: engine, store: SettingsStore(enabled: false)));
  await t.pump();
  return engine;
}

SynthState stateOf(WidgetTester t) =>
    Provider.of<SynthState>(t.element(find.byType(Scaffold)), listen: false);

void main() {
  for (final size in const [Size(844, 390), Size(640, 360), Size(1280, 720)]) {
    testWidgets('fills the screen without overflow at $size', (t) async {
      await pump(t, size: size);
      expect(t.takeException(), isNull);
      final kbs = t.widgetList(find.byType(KeyboardWidget)).length;
      expect(kbs, 2);
      // the two keyboard halves sit side by side at the bottom
      final a = t.getRect(find.byType(KeyboardWidget).first);
      final b = t.getRect(find.byType(KeyboardWidget).last);
      expect(a.right, lessThan(b.left));
      expect(a.bottom, closeTo(b.bottom, 1));
      expect(b.bottom, greaterThan(size.height * 0.9));
    });
  }

  testWidgets('two keyboards play independently (own octave, same pitch)', (t) async {
    final e = await pump(t);
    final left = t.getRect(find.byType(KeyboardWidget).first);
    final right = t.getRect(find.byType(KeyboardWidget).last);
    Offset keyAt(Rect r, int whiteIndex) =>
        Offset(r.left + r.width / 10 * (whiteIndex + 0.5), r.bottom - 8);

    // left: oct 0 → first C = 60. right: oct +1 → first C = 72, zone 1 → +128
    final gl = await t.startGesture(keyAt(left, 0));
    final gr = await t.startGesture(keyAt(right, 0));
    expect(e.log, ['on 60', 'on ${128 + 72}']);

    // right octave changes while a note is held: held note keeps its pitch
    stateOf(t).setOctave(1, 0);
    await t.pump();
    await gr.up();
    expect(e.log.last, 'off ${128 + 72}');

    final g2 = await t.startGesture(keyAt(right, 0));
    expect(e.log.last, 'on ${128 + 60}'); // new octave applies to new notes
    await g2.up();
    await gl.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('chord, glissando and black-key priority on one half', (t) async {
    final e = await pump(t);
    final kb = t.getRect(find.byType(KeyboardWidget).first);
    final w = kb.width / 10;
    Offset white(int i) => Offset(kb.left + w * (i + 0.5), kb.bottom - 10);

    final g1 = await t.startGesture(white(0));
    final g2 = await t.startGesture(white(2));
    final g3 = await t.startGesture(white(4));
    expect(e.log, ['on 60', 'on 64', 'on 67']);
    await g2.moveTo(white(3));
    expect(e.log.sublist(3), ['off 64', 'on 65']);
    await g1.up();
    await g2.up();
    await g3.up();
    expect(e.log.sublist(5).toSet(), {'off 60', 'off 65', 'off 67'});

    e.log.clear();
    final g = await t.startGesture(Offset(kb.left + w, kb.top + 6));
    expect(e.log, ['on 61']); // C#, not a white key
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('slider: drag changes the param, double-tap resets', (t) async {
    await pump(t);
    final state = stateOf(t);
    final label = find.text('CUTOFF').first; // left half
    expect(find.text('CUTOFF'), findsNWidgets(2)); // one per half
    final top = t.getCenter(label) - const Offset(0, 80);
    await t.dragFrom(t.getCenter(label) - const Offset(0, 40), const Offset(0, 60));
    await t.pump();
    final before = state.value(0, SynthParam.cutoff);
    await t.tapAt(top);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(top);
    await t.pump();
    expect(state.value(0, SynthParam.cutoff), SynthParam.cutoff.def);
    expect(before, isNot(SynthParam.cutoff.def));
    expect(state.value(1, SynthParam.cutoff), SynthParam.cutoff.def); // right half untouched
    await t.pump(const Duration(milliseconds: 500));
  });

  testWidgets('wave switch: sine / square / triangle per half', (t) async {
    final e = await pump(t);
    final state = stateOf(t);
    expect(find.text('TRIANGLE'), findsNWidgets(2)); // one switch per half
    expect(state.value(0, SynthParam.wave), 1); // square by default
    await t.tap(find.text('TRIANGLE').first);
    await t.pump();
    expect(state.value(0, SynthParam.wave), 2);
    expect(state.value(1, SynthParam.wave), 1); // right half untouched
    expect(e.params.last, (0, SynthParam.wave.id, 2.0));
    await t.tap(find.text('SINE').last);
    await t.pump();
    expect(state.value(1, SynthParam.wave), 0);
    expect(state.value(0, SynthParam.wave), 2);
    await t.pump(const Duration(milliseconds: 500));
  });

  testWidgets('octave slider is stepped -2..+2', (t) async {
    await pump(t);
    final state = stateOf(t);
    final r = t.getRect(find.byType(OctaveSlider).first);
    await t.tapAt(Offset(r.center.dx - 10, r.top + 30)); // top = +2
    await t.pump();
    expect(state.octave(0), 2);
    await t.tapAt(Offset(r.center.dx - 10, r.bottom - 33)); // bottom = -2
    await t.pump();
    expect(state.octave(0), -2);
    await t.tapAt(Offset(r.center.dx - 10, r.center.dy)); // middle = 0
    await t.pump();
    expect(state.octave(0), 0);
    await t.pump(const Duration(milliseconds: 500));
  });

  testWidgets('left slider changes only the left half; engine gets the right zone', (t) async {
    final e = await pump(t);
    final state = stateOf(t);
    state.set(1, SynthParam.volume, 0.2);
    expect(state.value(0, SynthParam.volume), SynthParam.volume.def);
    expect(state.value(1, SynthParam.volume), 0.2);
    expect(e.params.last, (1, SynthParam.volume.id, 0.2));
    await t.pump(const Duration(milliseconds: 100));
  });

  test('patch JSON round trip and clamping', () {
    final p = PatchConfig(name: 'X', values: {SynthParam.cutoff: 99999, SynthParam.wave: 1.4});
    expect(p[SynthParam.cutoff], 20000);
    expect(p[SynthParam.wave], 1); // discrete
    final back = PatchConfig.fromJson(p.toJson());
    for (final s in SynthParam.values) {
      expect(back[s], p[s]);
    }
    expect(SynthParam.cutoff.fromNorm(SynthParam.cutoff.toNorm(1234)), closeTo(1234, 1));
  });
}
