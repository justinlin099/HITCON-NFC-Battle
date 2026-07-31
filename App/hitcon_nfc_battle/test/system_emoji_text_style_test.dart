import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/widgets/system_emoji_text_style.dart';

void main() {
  test('emoji text style prefers native color emoji fonts', () {
    final style = systemEmojiTextStyle(fontSize: 24);

    expect(style.fontFamily, 'Noto Color Emoji');
    expect(style.fontFamilyFallback, <String>[
      'Apple Color Emoji',
      'Segoe UI Emoji',
      'Noto Emoji',
    ]);
    expect(style.fontFamily, isNot('Unifont'));
  });
}
