import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const List<String> _knownSystemEmojiFonts = <String>[
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Emoji',
];

String get systemEmojiFontFamily {
  if (kIsWeb) {
    return 'Noto Color Emoji';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
    TargetPlatform.windows => 'Segoe UI Emoji',
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux => 'Noto Color Emoji',
  };
}

List<String> get systemEmojiFontFallback => _knownSystemEmojiFonts
    .where((String family) => family != systemEmojiFontFamily)
    .toList(growable: false);

bool isEmojiGrapheme(String value) {
  if (value.contains('\uFE0F') || value.contains('\u20E3')) {
    return true;
  }
  for (final int rune in value.runes) {
    if ((rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2B00 && rune <= 0x2BFF) ||
        rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x203C ||
        rune == 0x2049 ||
        rune == 0x2122 ||
        rune == 0x2139 ||
        rune == 0x3030 ||
        rune == 0x303D ||
        rune == 0x3297 ||
        rune == 0x3299) {
      return true;
    }
  }
  return false;
}

TextStyle systemEmojiTextStyle({
  Color? color,
  double? fontSize,
  double? height,
  FontWeight? fontWeight,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
    fontFamily: systemEmojiFontFamily,
    fontFamilyFallback: systemEmojiFontFallback,
  );
}
