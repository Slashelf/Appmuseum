import 'package:flutter/material.dart';

/// Colores y textos que la guía ya muestra. No cambia el aspecto.
class GuidePalette {
  static const Color accent = Color(0xFFC6A15B);
  static const Color onAccent = Color(0xFF1A1408);
  static const Color background = Color(0xFF0C0B09);
  static const Color surface = Color(0xFF171512);
  static const Color detailBackground = background;
  static const Color white = Color(0xFFFFFFFF);
  static const Color card = surface;
  static const Color beaconOn = accent;
  static const Color exploreCard = surface;
  static const Color fieldFill = Color(0xFF241F18);
  static const Color ink = Color(0xFFF4EFE6);
  static const Color muted = Color(0xFFA39886);

  static const double radiusCard = 12;
  static const double radiusButton = 20;
  static const double radiusSheet = 32;
}

class AppFonts {
  static TextStyle poppins({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Cormorant Garamond',
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w600,
      color: color,
      height: height,
    );
  }
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: false,
      primarySwatch: Colors.brown,
      scaffoldBackgroundColor: GuidePalette.background,
      fontFamily: 'Poppins',
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: GuidePalette.accent,
        secondary: GuidePalette.accent,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: GuidePalette.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: GuidePalette.ink,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: GuidePalette.ink,
        ),
        bodyMedium: TextStyle(fontSize: 16, color: GuidePalette.ink),
        bodySmall: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: GuidePalette.ink,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: GuidePalette.white,
        elevation: 0,
      ),
    );
  }
}
