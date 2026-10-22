import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Hardware-style vertical fader on an off-white tile: value read-out on top,
/// groove with a chunky cap, label at the bottom.
///
/// Works on a normalised 0..1 position; [steps] > 0 makes it a stepped switch
/// (that many +1 positions). Double-tap calls [onReset]. Sized to work in a
/// tile as narrow as ~30 dp: the read-out above shows the current value / mode.
class VerticalSlider extends StatefulWidget {
  const VerticalSlider({
    super.key,
    required this.label,
    required this.norm,
    required this.valueText,
    required this.onChanged,
    this.onReset,
    this.steps = 0,
    this.trailing,
  });

  final String label;
  final double norm; // 0..1
  final String valueText;
  final ValueChanged<double> onChanged;
  /// Called on double-tap (reset to the default).
  final VoidCallback? onReset;
  final int steps;

  /// Shown to the right of the groove (e.g. the master level meter).
  final Widget? trailing;

  @override
  State<VerticalSlider> createState() => _VerticalSliderState();
}

class _VerticalSliderState extends State<VerticalSlider> {
  bool _touched = false;
  int _lastStep = -1;

  static const double _capH = 26;

  /// Travel margin of the cap centre. Smaller than half the cap height on
  /// purpose: the cap may overlap the gap around the slider, which gives the
  /// groove (and its tick marks) the whole height of the tile.
  static const double _inset = 4;

  void _set(double dy, double height) {
    // The cap centre follows the finger inside [inset, height - inset].
    final usable = height - 2 * _inset;
    final n = (1 - (dy - _inset) / usable).clamp(0.0, 1.0);
    final v = widget.steps > 0 ? (n * widget.steps).round() / widget.steps : n;
    if (widget.steps > 0) {
      final step = (v * widget.steps).round();
      if (step != _lastStep) {
        _lastStep = step;
        HapticFeedback.selectionClick();
      }
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: tileDecoration(radius: 7),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
      child: Column(children: [
        SizedBox(
          height: 13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.valueText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: _touched ? Hw.orange : Hw.inkSoft,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4), // air between the read-out and the fader
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) {
                setState(() => _touched = true);
                _set(d.localPosition.dy, box.maxHeight);
              },
              onPanUpdate: (d) => _set(d.localPosition.dy, box.maxHeight),
              onPanEnd: (_) => setState(() => _touched = false),
              onPanCancel: () => setState(() => _touched = false),
              onDoubleTap: widget.onReset,
              child: Row(children: [
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _FaderPainter(
                      norm: widget.norm,
                      active: _touched,
                      steps: widget.steps,
                      capH: _capH,
                      inset: _inset,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ]),
            );
          }),
        ),
        const SizedBox(height: 3),
        // Two-line labels ("LFO" / "RATE") are stacked; one-line labels are
        // centred in the same height so every tile lines up.
        SizedBox(
          height: 22,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  // two stacked words get a smaller font so both lines fit
                  fontSize: widget.label.contains('\n') ? 7.5 : 9,
                  height: 1.15,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                  color: Hw.ink),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter({
    required this.norm,
    required this.active,
    required this.steps,
    required this.capH,
    required this.inset,
  });
  final double norm;
  final bool active;
  final int steps;
  final double capH;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = inset, bottom = size.height - inset;
    double yOf(double n) => bottom - (bottom - top) * n;
    // tick marks shrink with the tile so they never touch the edge
    final reach = (size.width / 2 - 1.5).clamp(6.0, 14.0);
    final tickLen = reach * 0.45;

    // ticks at each step, or 11 ticks for continuous faders
    final ticks = steps > 0 ? steps + 1 : 11;
    final tickPaint = Paint()
      ..color = Hw.inkSoft
      ..strokeWidth = 1;
    for (var i = 0; i < ticks; i++) {
      final y = yOf(i / (ticks - 1));
      final major = steps > 0 || i % 5 == 0;
      final len = major ? tickLen : tickLen * 0.6;
      canvas.drawLine(Offset(cx - reach, y), Offset(cx - reach + len, y), tickPaint);
      canvas.drawLine(Offset(cx + reach - len, y), Offset(cx + reach, y), tickPaint);
    }

    // groove
    final groove = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - 3, top - 2, cx + 3, bottom + 2), const Radius.circular(3));
    canvas.drawRRect(groove, Paint()..color = Hw.knob);

    // fill (orange) from the bottom up to the cap
    final capY = yOf(norm.clamp(0.0, 1.0));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - 1.6, capY, cx + 1.6, bottom + 1), const Radius.circular(2)),
      Paint()..color = active ? Hw.orange : const Color(0xFFB85A14),
    );

    // cap
    final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, capY), width: (size.width - 4).clamp(16.0, 30.0), height: capH * 0.78),
        const Radius.circular(6));
    canvas.drawRRect(
        cap.shift(const Offset(0, 1.5)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(
        cap,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A4A4E), Color(0xFF151517)],
          ).createShader(cap.outerRect));
    canvas.drawRRect(
        cap,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = active ? Hw.orange : const Color(0xFF6A6A70));
    final half = ((size.width - 4).clamp(16.0, 30.0) / 2 - 4).clamp(4.0, 9.0);
    canvas.drawLine(Offset(cx - half, capY), Offset(cx + half, capY),
        Paint()
          ..color = active ? Hw.orange : Hw.led
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_FaderPainter o) =>
      o.norm != norm || o.active != active || o.steps != steps;
}
