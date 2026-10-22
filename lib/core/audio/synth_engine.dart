import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'synth_bindings.dart' as native;

/// What the UI needs from the audio layer.
abstract class SynthEngine {
  /// Opens the output device. Returns null on success, else an error message.
  Future<String?> start();

  void noteOn(int note, [double velocity = 0.85]);
  void noteOff(int note);
  void allNotesOff();
  /// Every keyboard half ([zone] 0 / 1) has its own, independent parameters.
  void setParam(int zone, int id, double value);

  /// Smoothed output peak 0..1 of one half (0 when silent).
  double peak(int zone);
  int get activeVoices;

  /// Fills [out] with the latest mono output samples (for the scope).
  void readScope(Float32List out);
  void dispose();
}

/// C++ DSP engine (miniaudio output) driven through dart:ffi.
///
/// There is deliberately no Dart isolate in the audio path: the audio thread
/// belongs to miniaudio, and a touch calls `synth_note_on` directly, which only
/// pushes into a lock-free ring buffer (a few nanoseconds, leaf call). The
/// rendering itself never touches the Dart VM.
class NativeSynthEngine implements SynthEngine {
  Pointer<Float>? _scope;
  int _scopeLen = 0;

  /// False until the native library loaded and the device opened; until then
  /// (or if that failed) every call is a no-op instead of throwing on each touch.
  bool _ok = false;

  @override
  Future<String?> start() async {
    try {
      final r = native.synthStart();
      _ok = r == 0;
      return _ok ? null : 'Audio device could not be opened (code $r)';
    } catch (e) {
      return 'Native synth library failed to load: $e';
    }
  }

  @override
  void noteOn(int note, [double velocity = 0.85]) => _ok ? native.synthNoteOn(note, velocity) : null;

  @override
  void noteOff(int note) => _ok ? native.synthNoteOff(note) : null;

  @override
  void allNotesOff() => _ok ? native.synthAllNotesOff() : null;

  @override
  void setParam(int zone, int id, double value) =>
      _ok ? native.synthSetParam(zone, id, value) : null;

  @override
  double peak(int zone) => _ok ? native.synthGetPeak(zone) : 0;

  @override
  int get activeVoices => _ok ? native.synthActiveVoices() : 0;

  @override
  void readScope(Float32List out) {
    if (!_ok) {
      out.fillRange(0, out.length, 0);
      return;
    }
    if (_scope == null || _scopeLen < out.length) {
      if (_scope != null) calloc.free(_scope!);
      _scope = calloc<Float>(out.length);
      _scopeLen = out.length;
    }
    native.synthGetScope(_scope!, out.length);
    out.setAll(0, _scope!.asTypedList(out.length));
  }

  @override
  void dispose() {
    if (_ok) native.synthDestroy();
    if (_scope != null) calloc.free(_scope!);
    _scope = null;
  }
}

/// Silent stand-in (tests, or when the device can't be opened).
class NullSynthEngine implements SynthEngine {
  final List<String> log = [];
  final List<(int zone, int id, double value)> params = [];
  @override
  Future<String?> start() async => null;
  @override
  void noteOn(int note, [double velocity = 0.85]) => log.add('on $note');
  @override
  void noteOff(int note) => log.add('off $note');
  @override
  void allNotesOff() => log.add('all off');
  @override
  void setParam(int zone, int id, double value) => params.add((zone, id, value));
  @override
  double peak(int zone) => 0;
  @override
  int get activeVoices => 0;
  @override
  void readScope(Float32List out) => out.fillRange(0, out.length, 0);
  @override
  void dispose() {}
}
