import 'package:flutter/material.dart';

const String systemEmojiFontFamily = 'Noto Color Emoji';

const List<String> systemEmojiFontFallback = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Emoji',
];

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
