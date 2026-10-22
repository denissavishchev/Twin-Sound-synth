import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/synth_param.dart';
import '../../state/audio_monitor.dart';
import '../../state/synth_state.dart';
import '../theme.dart';
import 'level_meter.dart';
import 'vertical_slider.dart';
import 'wave_switch.dart';

/// A [VerticalSlider] bound to one parameter of one keyboard half.
class ParamSlider extends StatelessWidget {
  const ParamSlider({
    super.key,
    required this.zone,
    required this.param,
    this.trailing,
  });
  final int zone;
  final SynthParam param;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final value = context.select<SynthState, double>(
      (s) => s.value(zone, param),
    );
    final state = context.read<SynthState>();
    return VerticalSlider(
      label: param.label,
      norm: param.toNorm(value),
      valueText: param.format(value),
      onReset: () => state.reset(zone, param),
      steps: param.scale == ParamScale.discrete
          ? (param.max - param.min).round()
          : 0,
      trailing: trailing,
      onChanged: (n) => state.set(zone, param, param.fromNorm(n)),
    );
  }
}

/// Octave switch of one keyboard half (-2 … +2).
class OctaveSlider extends StatelessWidget {
  const OctaveSlider({super.key, required this.zone});
  final int zone;

  @override
  Widget build(BuildContext context) {
    final oct = context.select<SynthState, int>((s) => s.octave(zone));
    final state = context.read<SynthState>();
    const lo = SynthState.minOctave, hi = SynthState.maxOctave;
    return VerticalSlider(
      label: 'OCT',
      norm: (oct - lo) / (hi - lo),
      valueText: oct > 0 ? '+$oct' : '$oct',
      steps: hi - lo,
      onReset: () => state.setOctave(zone, zone == 0 ? 0 : 1),
      onChanged: (n) => state.setOctave(zone, lo + (n * (hi - lo)).round()),
    );
  }
}

/// The black panel above one keyboard half: a complete, independent set of
/// vertical sliders in outlined logical groups —
/// a SINE / SQUARE / TRIANGLE switch on top, then outlined groups:
/// OSC (octave, detune) · FILTER (cutoff) · LFO (depth, rate, destination) ·
/// FX (delay time, delay mix, reverb) · OUT (volume).
class ZonePanel extends StatelessWidget {
  const ZonePanel({super.key, required this.zone});
  final int zone;

  static const double _gap = 3, _groupGap = 5;

  @override
  Widget build(BuildContext context) {
    final monitor = context.read<AudioMonitor>();

    ParamSlider p(SynthParam param, {Widget? trailing}) =>
        ParamSlider(zone: zone, param: param, trailing: trailing);

    Widget group(List<Widget> tiles) => Expanded(
      flex: tiles.length,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8A5528), width: 1),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Hw.panel,
        // flat bottom: the panel runs straight into the nameplate
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: [
          // tall enough that the light active pill has air above and below its text
        SizedBox(height: 30, child: WaveSwitch(zone: zone)),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                group([OctaveSlider(zone: zone), p(SynthParam.tune)]),
                const SizedBox(width: _groupGap),
                group([p(SynthParam.cutoff)]),
                const SizedBox(width: _groupGap),
                group([
                  p(SynthParam.lfoDepth),
                  p(SynthParam.lfoRate),
                  p(SynthParam.lfoDest),
                ]),
                const SizedBox(width: _groupGap),
                group([
                  p(SynthParam.delayTime),
                  p(SynthParam.delayMix),
                  p(SynthParam.reverbMix),
                ]),
                const SizedBox(width: _groupGap),
                group([
                  p(
                    SynthParam.volume,
                    trailing: LevelMeter(monitor: monitor, zone: zone),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
