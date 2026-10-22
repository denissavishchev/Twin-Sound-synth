import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/note_event.dart';
import '../theme.dart';

/// One piano key. Purely visual: [level] (1 = pressed, decaying to 0 on
/// release) drives a flat orange fill and a small "sink" of the key,
/// so the press/release animation never rebuilds the whole keyboard.
class KeyTile extends StatelessWidget {
  const KeyTile({super.key, required this.note, required this.level, this.label});
  final int note;
  final ValueListenable<double> level;

  /// Optional text on the key (the octave name on every C).
  final String? label;

  bool get _black => isBlackKey(note);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (_, v, _) {
        final t = Curves.easeOut.transform(v.clamp(0.0, 1.0));
        // Pressed = flat orange: no glow / shine, and the drop shadow under the key
        // fades out completely.
        final glow = [
          if (t < 0.99)
            BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.4 * (1 - t)),
                blurRadius: 3 * (1 - t),
                offset: Offset(0, 3 * (1 - t))),
        ];
        if (_black) {
          return Transform.translate(
            offset: Offset(0, 2 * t),
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(Hw.keyBlack, const Color(0xFFFF8A1F), t),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                border: Border.all(
                    color: Color.lerp(const Color(0xFF3A3A3D), const Color(0xFFFF8A1F), t)!,
                    width: 1),
                boxShadow: glow,
              ),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.only(bottom: 8),
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            // pale key → saturated orange as soon as it is pressed
            color: Color.lerp(Hw.keyWhite, const Color(0xFFFF8A1F), t),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            border: Border.all(
                color: Color.lerp(Hw.tileEdge, const Color(0xFFFF8A1F), t)!, width: 1),
            boxShadow: glow,
          ),
          child: label == null
              ? null
              : Text(label!,
                  style: TextStyle(
                      fontSize: 9,
                      color: Color.lerp(Hw.inkSoft, Colors.white, t),
                      fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}
