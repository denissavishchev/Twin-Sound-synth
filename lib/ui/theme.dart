import 'package:flutter/material.dart';

/// Palette taken from the reference hardware: pale grey chassis, black panels,
/// off-white tiles, a single orange accent and red LEDs.
class Hw {
  static const chassisTop = Color(0xFFD8D9DC);
  static const chassisBottom = Color(0xFFC4C5C9);
  static const panel = Color(0xFF0E0E10);
  static const tile = Color(0xFFE6E3E0);
  static const tileEdge = Color(0xFFF4F2F0);
  static const tileShade = Color(0xFFBDB9B5);
  static const ink = Color(0xFF151516);
  static const inkSoft = Color(0xFF6B6967);
  static const led = Color(0xFFFF3B30);
  static const orange = Color(0xFFFF7A1A);
  static const knob = Color(0xFF0A0A0B);
  static const keyWhite = Color(0xFFEFEEEC);
  static const keyBlack = Color(0xFF131314);
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Hw.chassisTop,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Hw.orange,
        brightness: Brightness.light,
        surface: Hw.tile,
      ),
      fontFamily: 'Helvetica Neue',
    );

/// The raised off-white tile every control sits on.
BoxDecoration tileDecoration({double radius = 9}) => BoxDecoration(
      color: Hw.tile,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Hw.tileEdge, width: 1),
      boxShadow: const [
        BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1.5)),
      ],
    );
