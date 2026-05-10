import 'package:flutter/material.dart';

enum PixelScheme { arcade, neon, sunset, forest, mono }

class PixelPalette {
  const PixelPalette({
    required this.bgDark,
    required this.bgMid,
    required this.bgLight,
    required this.accent,
    required this.accentBlue,
    required this.textWhite,
    required this.textGray,
    required this.success,
    required this.warning,
    required this.border,
  });

  final Color bgDark;
  final Color bgMid;
  final Color bgLight;
  final Color accent;
  final Color accentBlue;
  final Color textWhite;
  final Color textGray;
  final Color success;
  final Color warning;
  final Color border;
}

class PixelTheme {
  static const Map<PixelScheme, PixelPalette> schemes = <PixelScheme, PixelPalette>{
    PixelScheme.arcade: PixelPalette(
      bgDark: Color(0xFF001933),
      bgMid: Color(0xFF003D6B),
      bgLight: Color(0xFF004D7A),
      accent: Color(0xFFFFD700),
      accentBlue: Color(0xFF00D9FF),
      textWhite: Color(0xFFFFFFFF),
      textGray: Color(0xFFAAAAAA),
      success: Color(0xFF00FF00),
      warning: Color(0xFFFF0033),
      border: Color(0xFF005A8B),
    ),
    PixelScheme.neon: PixelPalette(
      bgDark: Color(0xFF12061D),
      bgMid: Color(0xFF28103F),
      bgLight: Color(0xFF4B1D67),
      accent: Color(0xFFFF4DFF),
      accentBlue: Color(0xFF00F5FF),
      textWhite: Color(0xFFF7F2FF),
      textGray: Color(0xFFC2B7D9),
      success: Color(0xFF64FF9A),
      warning: Color(0xFFFF5470),
      border: Color(0xFF7B3FF2),
    ),
    PixelScheme.sunset: PixelPalette(
      bgDark: Color(0xFF1B1020),
      bgMid: Color(0xFF40214D),
      bgLight: Color(0xFF7A355C),
      accent: Color(0xFFFFC857),
      accentBlue: Color(0xFFFF8A5B),
      textWhite: Color(0xFFFFF7F1),
      textGray: Color(0xFFE4CFCB),
      success: Color(0xFF7CFFCB),
      warning: Color(0xFFFF6B6B),
      border: Color(0xFFA94E7C),
    ),
    PixelScheme.forest: PixelPalette(
      bgDark: Color(0xFF0D1B16),
      bgMid: Color(0xFF123026),
      bgLight: Color(0xFF1E4A3B),
      accent: Color(0xFFB7F171),
      accentBlue: Color(0xFF66E2B3),
      textWhite: Color(0xFFF1FFF5),
      textGray: Color(0xFFC3D3CA),
      success: Color(0xFF9CFF6B),
      warning: Color(0xFFFF7E6B),
      border: Color(0xFF2D7158),
    ),
    PixelScheme.mono: PixelPalette(
      bgDark: Color(0xFF101010),
      bgMid: Color(0xFF222222),
      bgLight: Color(0xFF363636),
      accent: Color(0xFFF5F5F5),
      accentBlue: Color(0xFFBDBDBD),
      textWhite: Color(0xFFFFFFFF),
      textGray: Color(0xFFB0B0B0),
      success: Color(0xFFFFFFFF),
      warning: Color(0xFFFF6B6B),
      border: Color(0xFF707070),
    ),
  };

  static const PixelScheme defaultScheme = PixelScheme.arcade;

  static PixelPalette getPalette(PixelScheme scheme) => schemes[scheme] ?? schemes[defaultScheme]!;

  static String labelOf(PixelScheme scheme) {
    switch (scheme) {
      case PixelScheme.arcade:
        return 'Arcade';
      case PixelScheme.neon:
        return 'Neon';
      case PixelScheme.sunset:
        return 'Sunset';
      case PixelScheme.forest:
        return 'Forest';
      case PixelScheme.mono:
        return 'Mono';
    }
  }

  static late PixelPalette active;

  static Color get bgDark => active.bgDark;
  static Color get bgMid => active.bgMid;
  static Color get bgLight => active.bgLight;
  static Color get accent => active.accent;
  static Color get accentBlue => active.accentBlue;
  static Color get textWhite => active.textWhite;
  static Color get textGray => active.textGray;
  static Color get success => active.success;
  static Color get warning => active.warning;
  static Color get border => active.border;
}
