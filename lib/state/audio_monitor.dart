import 'package:flutter/foundation.dart';

import '../core/audio/synth_engine.dart';

/// Polled once per frame by the screen; the meters repaint from it without
/// rebuilding any widget.
class AudioMonitor extends ChangeNotifier {
  AudioMonitor(this.engine);
  final SynthEngine engine;

  /// Peak 0..1 of each keyboard half, with a held-then-falling ballistic.
  final List<double> levels = [0, 0];

  void poll() {
    for (var z = 0; z < levels.length; z++) {
      final p = engine.peak(z);
      levels[z] = p > levels[z] ? p : levels[z] * 0.9;
    }
    notifyListeners();
  }
}
