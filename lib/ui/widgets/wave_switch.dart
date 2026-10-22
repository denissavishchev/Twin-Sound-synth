import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/synth_param.dart';
import '../../state/synth_state.dart';
import '../theme.dart';

/// Horizontal 3-position switch for the oscillator shape of one keyboard half:
/// SINE · SQUARE · TRIANGLE. The active position lights up; tap or slide a
/// finger across to change it.
class WaveSwitch extends StatelessWidget {
  const WaveSwitch({super.key, required this.zone});
  final int zone;

  static const _names = ['SINE', 'SQUARE', 'TRIANGLE'];

  @override
  Widget build(BuildContext context) {
    final current = context.select<SynthState, int>((s) => s.value(zone, SynthParam.wave).round());
    final state = context.read<SynthState>();

    void pick(int i) {
      if (i == current) return;
      HapticFeedback.selectionClick();
      state.set(zone, SynthParam.wave, i.toDouble());
    }

    return LayoutBuilder(builder: (context, box) {
      int indexAt(double dx) => (dx / box.maxWidth * 3).floor().clamp(0, 2);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => pick(indexAt(d.localPosition.dx)),
        onPanUpdate: (d) => pick(indexAt(d.localPosition.dx)),
        child: Container(
          // air between the black bar's edge and the white pills (top / bottom)
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: Hw.knob,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF3A3A40)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: i == current ? Hw.tile : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 22,
                      height: 10,
                      child: CustomPaint(
                          painter: _WaveGlyph(i, i == current ? Hw.orange : const Color(0xFF8E8E95))),
                    ),
                    const SizedBox(width: 10), // space between the icon and the text
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_names[i],
                            style: TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w800,
                                color: i == current ? Hw.ink : const Color(0xFF8E8E95))),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

/// Little picture of one period: 0 sine, 1 square, 2 triangle.
class _WaveGlyph extends CustomPainter {
  _WaveGlyph(this.kind, this.color);
  final int kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, mid = h / 2, a = h * 0.42;
    final path = Path();
    switch (kind) {
      case 0:
        for (var i = 0; i <= 24; i++) {
          final x = w * i / 24;
          final y = mid - a * math.sin(2 * math.pi * i / 24);
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
      case 1:
        path
          ..moveTo(0, mid + a)
          ..lineTo(0, mid - a)
          ..lineTo(w / 2, mid - a)
          ..lineTo(w / 2, mid + a)
          ..lineTo(w, mid + a);
      default:
        path
          ..moveTo(0, mid)
          ..lineTo(w / 4, mid - a)
          ..lineTo(w * 3 / 4, mid + a)
          ..lineTo(w, mid);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_WaveGlyph o) => o.kind != kind || o.color != color;
}
