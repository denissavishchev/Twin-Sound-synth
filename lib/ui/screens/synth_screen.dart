import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/audio/synth_engine.dart';
import '../../state/audio_monitor.dart';
import '../../state/synth_state.dart';
import '../theme.dart';
import '../widgets/control_panel.dart';
import '../widgets/keyboard_widget.dart';

/// Whole screen (inside the safe area). Each keyboard half is an independent
/// synth: its own slider panel on top, its keys below.
class SynthScreen extends StatefulWidget {
  const SynthScreen({super.key});

  @override
  State<SynthScreen> createState() => _SynthScreenState();
}

class _SynthScreenState extends State<SynthScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    final monitor = context.read<AudioMonitor>();
    _ticker = createTicker((_) => monitor.poll())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select<SynthState, String?>((s) => s.engineError);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Hw.chassisTop, Hw.chassisBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            // Extra side padding: the safe area doesn't cover rounded screen
            // corners, which would clip the panel and the last keys.
            padding: const EdgeInsets.fromLTRB(14, 6, 30, 6),
            child: Stack(children: [
              Column(children: [
                const Expanded(
                  flex: 11,
                  child: Row(children: [
                    Expanded(child: ZonePanel(zone: 0)),
                    SizedBox(width: 8),
                    Expanded(child: ZonePanel(zone: 1)),
                  ]),
                ),
                const _NamePlate(),
                Expanded(flex: 9, child: _KeyboardDeck(engine: context.read<SynthEngine>())),
              ]),
              if (error != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Material(
                    color: Hw.led,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(error, style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _KeyboardDeck extends StatelessWidget {
  const _KeyboardDeck({required this.engine});
  final SynthEngine engine;

  @override
  Widget build(BuildContext context) {
    Widget half(int zone) => Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF9A9B9F),
              // flat top: the keys sit directly under the nameplate
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 4),
              child: Selector<SynthState, int>(
                selector: (_, s) => s.octave(zone),
                builder: (_, oct, _) =>
                    KeyboardWidget(engine: engine, zone: zone, octave: oct),
              ),
            ),
          ),
        );

    return Row(children: [half(0), const SizedBox(width: 8), half(1)]);
  }
}

/// Brand strip between the sliders and the keys.
class _NamePlate extends StatelessWidget {
  const _NamePlate();

  /// Change these two to rename the instrument.
  static const String brand = 'DEVIS LABORATORY';
  static const String model = 'TWIN SOUND';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      color: Hw.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        const Expanded(child: Divider(color: Color(0xFF2C2C31), height: 1)),
        const SizedBox(width: 10),
        const Text(brand,
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.2)),
        const SizedBox(width: 8),
        Container(width: 4, height: 4, decoration: const BoxDecoration(color: Hw.orange, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        const Text(model,
            style: TextStyle(
                color: Hw.orange, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFF2C2C31), height: 1)),
      ]),
    );
  }
}
