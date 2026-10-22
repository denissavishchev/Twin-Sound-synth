import 'package:flutter/material.dart';

import '../../state/audio_monitor.dart';
import '../theme.dart';

/// Vertical LED-segment peak meter (green → orange → red).
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.monitor, required this.zone});
  final AudioMonitor monitor;
  final int zone;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 4,
        child: CustomPaint(painter: _MeterPainter(monitor, zone), child: const SizedBox.expand()),
      );
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.m, this.zone) : super(repaint: m);
  final AudioMonitor m;
  final int zone;

  @override
  void paint(Canvas canvas, Size size) {
    const segs = 16;
    final h = size.height / segs;
    final lit = (m.levels[zone].clamp(0.0, 1.0) * segs).ceil();
    for (var i = 0; i < segs; i++) {
      final f = (i + 1) / segs;
      final color = f > 0.86 ? Hw.led : (f > 0.65 ? Hw.orange : const Color(0xFF3DDC84));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, size.height - (i + 1) * h + 1, size.width, h - 1.8),
          const Radius.circular(1.5),
        ),
        Paint()..color = i < lit ? color : const Color(0xFFCFCBC7),
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter o) => false; // repaints via the listenable
}
