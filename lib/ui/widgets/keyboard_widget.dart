import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/audio/synth_engine.dart';
import '../../models/note_event.dart';
import 'key_tile.dart';

/// One half of the split keyboard (17 keys = 1½ octaves, C4 … E5 by default).
///
/// Raw pointer events go straight to the engine: no gesture arena, no waiting
/// for a tap to be recognised, no `setState` on touch — the visual level of each
/// key is a separate [ValueNotifier] animated by a ticker.
///
/// * [zone] (0 / 1) keeps the two halves independent inside the engine, so the
///   same pitch held on both halves never cuts each other off
/// * [octave] shifts the half by whole octaves; a held note keeps the pitch it
///   started with when the octave changes
/// * every finger is tracked by its pointer id (chords, several fingers)
/// * dragging a finger onto another key plays it (glissando)
/// * the vertical touch position sets the velocity (lower on the key = harder)
class KeyboardWidget extends StatefulWidget {
  const KeyboardWidget({
    super.key,
    required this.engine,
    required this.zone,
    required this.octave,
    this.firstNote = 60, // C4 — phone speakers are weak below ~200 Hz
    this.keyCount = 17,
  });

  final SynthEngine engine;
  final int zone;
  final int octave;
  final int firstNote;
  final int keyCount;

  @override
  State<KeyboardWidget> createState() => _KeyboardWidgetState();
}

class _KeyboardWidgetState extends State<KeyboardWidget> with SingleTickerProviderStateMixin {
  static const double _releaseSeconds = 0.25;
  static const double _blackWidthRatio = 0.62;
  static const double _blackHeightRatio = 0.6;

  late final List<int> _notes; // visual pitches, before the octave shift
  late final List<int> _whites;
  late final Map<int, ValueNotifier<double>> _levels;
  final Map<int, int> _pointerNote = {}; // pointer → visual note it holds
  final Map<int, int> _pointerKey = {}; // pointer → engine key it started
  final Map<int, int> _holds = {}; // engine key → number of fingers on it
  final Map<int, int> _keyVisual = {}; // engine key → visual note (for the light)
  final Set<int> _fading = {};
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _notes = [for (var i = 0; i < widget.keyCount; i++) widget.firstNote + i];
    _whites = [for (final n in _notes) if (!isBlackKey(n)) n];
    _levels = {for (final n in _notes) n: ValueNotifier(0.0)};
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final key in _pointerKey.values) {
      widget.engine.noteOff(key);
    }
    for (final l in _levels.values) {
      l.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- geometry

  double _whiteW(double w) => w / _whites.length;

  double _blackLeft(int note, double w) {
    final whiteIndex = _whites.indexOf(note - 1);
    final bw = _whiteW(w) * _blackWidthRatio;
    return (whiteIndex + 1) * _whiteW(w) - bw / 2;
  }

  int? _noteAt(Offset p, Size size) {
    if (p.dx < 0 || p.dy < 0 || p.dx >= size.width || p.dy >= size.height) return null;
    final bw = _whiteW(size.width) * _blackWidthRatio;
    if (p.dy < size.height * _blackHeightRatio) {
      for (final n in _notes) {
        if (!isBlackKey(n)) continue;
        final l = _blackLeft(n, size.width);
        if (p.dx >= l && p.dx < l + bw) return n;
      }
    }
    final i = (p.dx / _whiteW(size.width)).floor().clamp(0, _whites.length - 1);
    return _whites[i];
  }

  double _velocity(Offset p, Size size, int note) {
    final h = isBlackKey(note) ? size.height * _blackHeightRatio : size.height;
    return (0.7 + 0.3 * (p.dy / h)).clamp(0.7, 1.0).toDouble();
  }

  int _keyFor(int visualNote) => engineKey(widget.zone, visualNote + 12 * widget.octave);

  // --------------------------------------------------------------- touches

  void _press(int pointer, int visual, double velocity) {
    final key = _keyFor(visual);
    _pointerNote[pointer] = visual;
    _pointerKey[pointer] = key;
    final n = (_holds[key] ?? 0) + 1;
    _holds[key] = n;
    _keyVisual[key] = visual;
    if (n == 1) widget.engine.noteOn(key, velocity);
    _fading.remove(visual);
    _levels[visual]!.value = 1;
  }

  void _release(int pointer) {
    final key = _pointerKey.remove(pointer);
    final visual = _pointerNote.remove(pointer);
    if (key == null || visual == null) return;
    final n = (_holds[key] ?? 1) - 1;
    if (n > 0) {
      _holds[key] = n;
      return;
    }
    _holds.remove(key);
    _keyVisual.remove(key);
    widget.engine.noteOff(key);
    // keep the light on while another finger still holds this visual key
    if (!_pointerNote.containsValue(visual)) {
      _fading.add(visual);
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  void _down(PointerDownEvent e, Size size) {
    final note = _noteAt(e.localPosition, size);
    if (note == null) return;
    _press(e.pointer, note, _velocity(e.localPosition, size, note));
  }

  void _move(PointerMoveEvent e, Size size) {
    final old = _pointerNote[e.pointer];
    if (old == null) return;
    final note = _noteAt(e.localPosition, size);
    if (note == null || note == old) return;
    _release(e.pointer);
    _press(e.pointer, note, _velocity(e.localPosition, size, note));
  }

  void _up(PointerEvent e) => _release(e.pointer);

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.016 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    for (final n in _fading.toList()) {
      final l = _levels[n]!;
      final v = math.max(0.0, l.value - dt / _releaseSeconds);
      l.value = v;
      if (v == 0) _fading.remove(n);
    }
    if (_fading.isEmpty) _ticker.stop();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final ww = _whiteW(size.width);
      final bw = ww * _blackWidthRatio;
      String? label(int n) => n % 12 == 0 ? noteName(n + 12 * widget.octave) : null;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _down(e, size),
        onPointerMove: (e) => _move(e, size),
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(children: [
          Row(children: [
            for (final n in _whites)
              SizedBox(width: ww, child: KeyTile(note: n, level: _levels[n]!, label: label(n))),
          ]),
          for (final n in _notes)
            if (isBlackKey(n))
              Positioned(
                left: _blackLeft(n, size.width),
                top: 0,
                width: bw,
                height: size.height * _blackHeightRatio,
                child: KeyTile(note: n, level: _levels[n]!),
              ),
        ]),
      );
    });
  }
}
