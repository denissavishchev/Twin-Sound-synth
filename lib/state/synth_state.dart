import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/audio/synth_engine.dart';
import '../models/patch_config.dart';
import '../models/synth_param.dart';
import '../services/settings_store.dart';

/// The two keyboard halves ("zones") are fully independent synths: each has its
/// own patch (cutoff, LFO, delay, reverb, volume …) and its own octave.
///
/// Every parameter change updates the immutable [PatchConfig] of that zone and is
/// forwarded to the engine, where it is smoothed on the audio thread.
class SynthState extends ChangeNotifier {
  SynthState(this.engine, [SettingsStore? store]) : _store = store ?? SettingsStore(enabled: false);

  static const int zones = 2;
  static const int minOctave = -2, maxOctave = 2;

  final SynthEngine engine;
  final SettingsStore _store;
  Timer? _saveTimer;

  final List<PatchConfig> patches = [
    PatchConfig(name: 'Left'),
    PatchConfig(name: 'Right'),
  ];
  String? engineError;

  /// Octave shift of each half. Defaults: left = base, right = one above.
  final List<int> _octaves = [0, 1];

  double value(int zone, SynthParam p) => patches[zone][p];
  int octave(int zone) => _octaves[zone];

  Future<void> start() async {
    await _restore();
    engineError = await engine.start();
    debugPrint(engineError == null ? 'synth: audio engine running' : 'synth: $engineError');
    for (var z = 0; z < zones; z++) {
      for (final p in SynthParam.values) {
        engine.setParam(z, p.id, patches[z][p]);
      }
    }
    notifyListeners();
  }

  void set(int zone, SynthParam p, double v) {
    v = p.clamp(v);
    if (patches[zone][p] == v) return;
    patches[zone] = patches[zone].copyWith(param: p, value: v);
    engine.setParam(zone, p.id, v);
    _scheduleSave();
    notifyListeners();
  }

  void reset(int zone, SynthParam p) => set(zone, p, p.def);

  void setOctave(int zone, int value) {
    final v = value.clamp(minOctave, maxOctave);
    if (_octaves[zone] == v) return;
    _octaves[zone] = v;
    _scheduleSave();
    notifyListeners();
  }

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> toJson() => {
        'version': 1,
        'zones': [for (final p in patches) p.toJson()],
        'octaves': _octaves,
      };

  Future<void> _restore() async {
    final data = await _store.load();
    if (data == null) return;
    try {
      final zones = data['zones'] as List;
      for (var z = 0; z < SynthState.zones && z < zones.length; z++) {
        patches[z] = PatchConfig.fromJson(Map<String, dynamic>.from(zones[z] as Map));
      }
      final oct = data['octaves'] as List;
      for (var z = 0; z < SynthState.zones && z < oct.length; z++) {
        _octaves[z] = (oct[z] as num).round().clamp(minOctave, maxOctave);
      }
    } catch (_) {
      // unexpected shape: keep whatever was applied, defaults for the rest
    }
  }

  /// Saves shortly after the last change (a slider drag fires many changes).
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  /// Writes the settings now (also called when the app goes to the background).
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _store.save(toJson());
  }

  void panic() => engine.allNotesOff();

  @override
  void dispose() {
    _saveTimer?.cancel();
    engine.dispose();
    super.dispose();
  }
}
