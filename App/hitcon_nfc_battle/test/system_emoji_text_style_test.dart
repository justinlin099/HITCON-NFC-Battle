import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_card_face.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/widgets/system_emoji_text_style.dart';

void main() {
  test('emoji text style prefers native color emoji fonts', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final style = systemEmojiTextStyle(fontSize: 24);

    expect(style.fontFamily, 'Noto Color Emoji');
    expect(style.fontFamilyFallback, contains('Apple Color Emoji'));
    expect(style.fontFamilyFallback, contains('Segoe UI Emoji'));
    expect(style.fontFamily, isNot('Unifont'));
  });

  test('emoji text style uses the Apple emoji font on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(systemEmojiTextStyle().fontFamily, 'Apple Color Emoji');
  });

  test(
    'emoji grapheme detection includes text and emoji presentation blocks',
    () {
      expect(isEmojiGrapheme('🙂'), isTrue);
      expect(isEmojiGrapheme('⭐'), isTrue);
      expect(isEmojiGrapheme('⬛'), isTrue);
      expect(isEmojiGrapheme('⌨️'), isTrue);
      expect(isEmojiGrapheme('1️⃣'), isTrue);
      expect(isEmojiGrapheme('A'), isFalse);
    },
  );

  testWidgets('card attributes render supplemental symbols as native emoji', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 508,
              child: PixelCardFace(
                title: 'TEST',
                attributeEmoji: '',
                attributeLabel: '🙂 Smile  🐈 Cat  ⬛ Square',
                cardColor: const Color(0xFF7A233D),
                showText: true,
                image: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final RichText attributeText = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere(
            (RichText widget) => widget.text.toPlainText().contains('Square'),
          );
      final TextSpan root = attributeText.text as TextSpan;
      final TextSpan square = root.children!.whereType<TextSpan>().firstWhere(
        (TextSpan span) => span.text == '⬛',
      );

      expect(square.style?.fontFamily, 'Noto Color Emoji');
      expect(square.style?.fontFamily, isNot('Unifont'));
      expect(attributeText.strutStyle?.forceStrutHeight, isTrue);
      expect(attributeText.strutStyle?.fontSize, 10);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS emoji attribute rows keep a fixed compact line height', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 136,
              height: 216,
              child: PixelCardFace(
                title: 'TEST',
                attributeEmoji: '✨💻🔥',
                attributeLabel: 'MAGIC / LAPTOP / FIRE',
                attributeMaxLines: 3,
                stackAttributePairs: true,
                cardColor: Color(0xFF7A233D),
                showText: true,
                image: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      final Finder attributeFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is RichText && widget.text.toPlainText().contains('MAGIC'),
      );
      final RichText attributeText = tester.widget<RichText>(attributeFinder);

      expect(attributeText.strutStyle?.forceStrutHeight, isTrue);
      expect(attributeText.strutStyle?.fontSize, 10);
      expect(attributeText.strutStyle?.height, 1.15);
      expect(tester.getSize(attributeFinder).height, closeTo(36, 0.1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
